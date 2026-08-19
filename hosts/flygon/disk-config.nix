{...}: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b4a6e03f5";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/efi";
              mountOptions = ["fmask=0077" "dmask=0077"];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "flygon-crypt";
              settings = {
                allowDiscards = true;
              };
              passwordFile = "/tmp/flygon-luks.key";
              content = {
                type = "lvm_pv";
                vg = "flygon";
              };
            };
          };
        };
      };
    };

    lvm_vg.flygon = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "68G";
          content = {
            type = "swap";
            resumeDevice = true;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["noatime"];
          };
        };
      };
    };
  };
}
