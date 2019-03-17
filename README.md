Various scripts i created (ayufan) based on @longsleep changes to help with automated Linux building.

## License

These scripts are made available under the MIT license in the hope they might be useful to others. See LICENSE.txt for details.


`apt install binfmt-support binfmtc bsdtar mtools u-boot-tools pv bc sunxi-tools gcc automake make curl qemu dosfstoolsc lib32z1 lib32z1-dev qemu-user-static dosfstools figlet device-tree-compiler debootstrap`

`echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > /usr/lib/binfmt.d/qemu-aarch64-static.conf`

`sudo service systemd-binfmt restart`
