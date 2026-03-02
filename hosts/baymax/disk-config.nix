_: let
  fsOpts = {
    mountpoint = "none";
    canmount = "off";
    compression = "zstd";
    atime = "off";
    acltype = "posixacl";
    xattr = "sa";
    dnodesize = "auto";
    normalization = "formD";
    encryption = "aes-256-gcm";
    keyformat = "passphrase";
    "com.sun:auto-snapshot" = "false";
  };
in {
  disko.devices = {
    disk = {
      system = {
        type = "disk";
        device = "/dev/disk/by-id/ata-512GB_SSD_MQ23W96605594";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      data = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_20250501B1514";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "data";
              };
            };
          };
        };
      };

      archive = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500eb0059f5";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "archive";
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = fsOpts // {keylocation = "prompt";};
        postCreateHook = ''
          zfs list -t snapshot -H -o name | grep -E '^rpool/root@blank$' \
            || zfs snapshot rpool/root@blank
        '';

        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              mountpoint = "legacy";
              canmount = "noauto";
            };
          };

          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };

          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
          };

          "persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
          };

          "persistHost" = {
            type = "zfs_fs";
            mountpoint = "/persist/host";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
          };

          "reserved" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              canmount = "off";
              refreservation = "10G";
            };
          };
        };
      };

      data = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = fsOpts // {keylocation = "file:///persist/host/secrets/zfs/data.key";};
        datasets = {
          "reserved" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              canmount = "off";
              refreservation = "20G";
            };
          };

          "persistSave" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
            mountpoint = "/persist/save";
          };

          "cache" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
            mountpoint = "/persist/cache";
          };
        };
      };

      archive = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "off";
        };
        rootFsOptions = fsOpts // {keylocation = "file:///persist/host/secrets/zfs/data.key";};
        datasets = {
          "reserved" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              canmount = "off";
              refreservation = "20G";
            };
          };

          "media" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
            mountpoint = "/archive";
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=8s"
            ];
          };

          "replica" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
            mountpoint = "/archive/replica";
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=8s"
            ];
          };
        };
      };
    };
  };
}
