const env = process.env;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const header = (token) =>
  'MediaBrowser Client="Configure", Device="Configure", DeviceId="jellyfin-configure", Version="1.0"' +
  (token ? ', Token="' + token + '"' : '');

async function jellyfin(method, path, body, token) {
  const res = await fetch(env.JELLYFIN_URL + path, {
    method: method,
    headers: { Authorization: header(token), 'Content-Type': 'application/json', Accept: 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(method + ' ' + path + ': ' + res.status);
  const text = await res.text();
  return text ? JSON.parse(text) : undefined;
}

async function configure() {
  let info;
  for (let i = 0; i < 120 && !info; i++) { // 10 minutes, a huge library can be slow to start
    try {
      info = await jellyfin('GET', '/System/Info/Public');
    } catch (e) {
      console.log('waiting for jellyfin: ' + e.message);
      await sleep(5000);
    }
  }
  if (!info) throw new Error('jellyfin is not reachable');

  if (!info.StartupWizardCompleted) {
    console.log('completing the setup wizard');
    await jellyfin('POST', '/Startup/Configuration', { UICulture: 'en-US', MetadataCountryCode: 'FR', PreferredMetadataLanguage: 'en' });
    await jellyfin('GET', '/Startup/User'); // creates the default user the next call renames
    await jellyfin('POST', '/Startup/User', { Name: env.JELLYFIN_USER, Password: env.JELLYFIN_PASSWORD });
    // no `/Startup/RemoteAccess`: it saves `network.xml`, which is the read only ConfigMap (remote access is enabled in it)
    await jellyfin('POST', '/Startup/Complete');
  }

  const login = await jellyfin('POST', '/Users/AuthenticateByName', { Username: env.JELLYFIN_USER, Pw: env.JELLYFIN_PASSWORD });
  const token = login.AccessToken;

  // the name of the server (the pod name by default) is the name of the cluster
  const system = await jellyfin('GET', '/System/Configuration', undefined, token);
  if (system.ServerName !== env.SERVER_NAME) {
    await jellyfin('POST', '/System/Configuration', Object.assign({}, system, { ServerName: env.SERVER_NAME }), token);
    console.log('server name set to ' + env.SERVER_NAME);
  }

  // https://github.com/9p4/jellyfin-plugin-sso/blob/main/providers.md#authelia (the plugin answers 404 until it is loaded)
  // `Add` replaces the provider: the links of the SSO users to the users of jellyfin are kept (else a user whose
  // name differs from the one of the SSO is created again)
  const known = await jellyfin('GET', '/sso/OID/Get', undefined, token).catch(() => ({}));
  const previous = (known.authelia || known.Authelia || {});
  const canonicalLinks = previous.canonicalLinks || previous.CanonicalLinks;
  await jellyfin('POST', '/sso/OID/Add/authelia', Object.assign({
    oidEndpoint: env.ISSUER_URL,
    oidClientId: env.CLIENT_ID,
    oidSecret: env.CLIENT_SECRET,
    enabled: true,
    enableAuthorization: true, // the administrators and the access come from the groups, at each login
    enableAllFolders: true,
    enabledFolders: [],
    roles: ['app_jellyfin', 'role_admin'],
    adminRoles: ['role_admin'],
    roleClaim: 'groups',
    oidScopes: ['groups'],
    disablePushedAuthorization: true, // authelia does not require it
    schemeOverride: 'https', // the redirect uri, jellyfin sees the http of the gateway to the pod
  }, canonicalLinks ? { canonicalLinks: canonicalLinks } : {}), token);

  // the button of the login page, the other ways to sign in (user list, manual form, quick connect, forgotten
  // password) and the change of password of the profile are hidden: the password is the one of authelia
  const hidden = [
    '.manualLoginForm', '.visualLoginForm', '.btnManual', '.btnQuick', '.btnForgotPassword', '.btnSelectServer',
    '.updatePasswordForm', '.passwordSection',
  ].join(', ') + ' { display: none !important; }';
  const branding = await jellyfin('GET', '/System/Configuration/branding', undefined, token);
  await jellyfin('POST', '/System/Configuration/branding', Object.assign({}, branding, {
    LoginDisclaimer:
      '<form action="' + env.PUBLIC_URL + '/sso/OID/start/authelia">' +
      '<button class="raised block emby-button button-submit">Sign in with Authelia</button></form>',
    CustomCss: 'a.raised.emby-button { padding: 0.9em 1em; color: inherit !important; } .disclaimerContainer { display: block; } ' + hidden,
  }), token);
}

// one pass, the container repeats it (the script is read again each time: a change of it applies without a restart)
configure().then(() => console.log('jellyfin configured')).catch((e) => {
  console.log('jellyfin is not configured: ' + e.message);
  process.exit(1);
});
