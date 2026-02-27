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
        device = "/dev/disk/by-id/usb-Seagate_Portable_NT3F4401-0:0";
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

      backup = {
        type = "disk";
        device = "/dev/disk/by-id/usb-ADATA_HV611_457293242024-0:0";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "backup";
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
        };
        rootFsOptions = fsOpts // {keylocation = "file:///persist/secrets/zfs/data.key";};
        datasets = {
          "apps" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/mnt/data";
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=8s"
            ];
          };
        };
      };

      backup = {
        type = "zpool";
        options = {
          ashift = "12";
        };
        rootFsOptions = fsOpts // {keylocation = "file:///persist/secrets/zfs/backup.key";};
        datasets = {
          "main" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/mnt/backup";
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
