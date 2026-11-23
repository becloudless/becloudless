# The files that Stalwart downloads from GitHub, so the pod needs no access to GitHub: an init container copies /assets, and Stalwart reads them with
# `file://` URLs (see app-stalwart):
#  - webui.zip: the web UI (`resourceUrl` of the Application), without it /admin and /account are a 404;
#  - spam-filter-rules.json.gz: the rules of the spam filter (`spamFilterRulesUrl`);
#  - origin-asn-*.csv, user-country-*.csv: the ASN and country tables of the IPs (`asnUrls` and `geoUrls`), the default source of Stalwart. They change every
#    day, the image is built again every week (.github/workflows/docker-assets.yaml).
FROM --platform=$BUILDPLATFORM alpine:3.24.4 AS fetch

RUN apk add --no-cache curl unzip

# renovate: datasource=github-releases depName=stalwartlabs/webui
ARG WEBUI_VERSION=v2.1.1
# renovate: datasource=github-releases depName=stalwartlabs/spam-filter
ARG SPAM_FILTER_VERSION=v3.0.4
# the release `latest` is replaced by its publisher with the new tables: there is no version to pin
ARG IP_LOCATION_DB_URL=https://github.com/sapics/ip-location-db/releases/download/latest

WORKDIR /assets

RUN set -eu; \
    download() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$1" "$2"; }; \
    download webui.zip "https://github.com/stalwartlabs/webui/releases/download/${WEBUI_VERSION}/webui.zip"; \
    download spam-filter-rules.json.gz "https://github.com/stalwartlabs/spam-filter/releases/download/${SPAM_FILTER_VERSION}/spam-filter-rules.json.gz"; \
    for table in origin-asn-ipv4 origin-asn-ipv6 user-country-ipv4 user-country-ipv6; do \
      download "${table}.csv" "${IP_LOCATION_DB_URL}/${table}.csv"; \
    done

# a failed or truncated download must fail the build, not ship an empty file that Stalwart would load without a word
RUN set -eu; \
    unzip -p webui.zip stalwart-app.json | grep -q '"id":"webui"'; \
    gzip -t spam-filter-rules.json.gz; \
    for table in origin-asn-ipv4 origin-asn-ipv6 user-country-ipv4 user-country-ipv6; do \
      test "$(wc -l < "${table}.csv")" -gt 1000 || { echo "${table}.csv is too small"; exit 1; }; \
    done; \
    chmod 0444 /assets/*

FROM alpine:3.24.4

COPY --from=fetch /assets /assets
