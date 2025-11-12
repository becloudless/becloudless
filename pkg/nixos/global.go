package nixos

func GlobalEdit(name string) error {
	//globalDir := path.Join(bcl.BCL.Repository.Root, "nixos", "modules", "nixos", "global")
	//
	//if err := os.MkdirAll(globalDir, 0755); err != nil {
	//	return errs.WithE(err, "Failed to create group dir")
	//}
	//
	//hostAgePublic, _, err := security.Ed25519ToPublicAndPrivateAgeKeys(hostPriv)
	//if err != nil {
	//	return err
	//}
	//
	//adminPub, _, err := security.Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(path.Join(bcl.BCL.Home, bcl.PathSecrets, bcl.PathEd25519KeyFile))
	//if err != nil {
	//	return err
	//}
	//
	//if err := createSopsConfigFile(globalDir, []string{adminPub}); err != nil {
	//	return errs.WithE(err, "Failed to create group sops configuration file")
	//}
	//
	//content := GroupSecretFile{
	//	SshHostEd25519Key: string(hostPriv),
	//}
	//secretFile := path.Join(groupDir, "default.secrets.yaml")
	//if err = utils.YamlMarshalToFile(secretFile, content, 0600); err != nil {
	//	_ = os.Unset(secretFile)
	//	return errs.WithE(err, "Failed to create unencrypted secret file")
	//}
	//
	//sopsRunner := runner.NewNixShellRunner(&runner.LocalRunner{}, "sops")
	//if err = sopsRunner.ExecCmd("sops", "--config", path.Join(groupDir, security.SopsConfigFileName), "-i", "-e", secretFile); err != nil {
	//	_ = os.Unset(secretFile)
	//	return errs.WithE(err, "Failed to encrypt secret file")
	//}

	// create yaml file
	// create nix file
	return nil
}
