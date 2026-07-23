// Config backup tests cover portable account snapshots without copying caches.
package config

import "testing"

func TestExportAndRestoreConfigBackupPreservesBackupTarget(t *testing.T) {
	setTestHome(t, t.TempDir())
	alpha := validTestConfig()
	alpha.Endpoint = "https://alpha.example"
	if err := SaveProfile("alpha", alpha); err != nil {
		t.Fatal(err)
	}
	if err := SetActiveProfile("alpha"); err != nil {
		t.Fatal(err)
	}
	if err := ReorderProfiles([]string{"alpha"}); err != nil {
		t.Fatal(err)
	}
	settings := ConfigBackupSettings{Enabled: true, Target: ConfigBackupTarget{ProfileName: "alpha", Bucket: "backup", BackupPassword: "test-passphrase"}}
	if err := SaveConfigBackupSettings(settings); err != nil {
		t.Fatal(err)
	}
	archive, err := ExportConfigBackup()
	if err != nil {
		t.Fatal(err)
	}
	if err := SaveProfile("extra", validTestConfig()); err != nil {
		t.Fatal(err)
	}
	if err := RestoreConfigBackup(archive); err != nil {
		t.Fatal(err)
	}
	profiles, err := ListProfiles()
	if err != nil {
		t.Fatal(err)
	}
	if len(profiles) != 1 || profiles[0].Name != "alpha" {
		t.Fatalf("profiles after restore = %#v", profiles)
	}
	got, err := LoadConfigBackupSettings()
	if err != nil {
		t.Fatal(err)
	}
	if !got.Enabled || got.Target.ProfileName != "alpha" || got.Target.Bucket != "backup" {
		t.Fatalf("backup target lost: %#v", got)
	}
}
