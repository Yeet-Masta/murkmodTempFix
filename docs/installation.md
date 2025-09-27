# Installation

murkmod has seen many iterations, and due to this, there are many methods available to install it. All previously functional methods of installation are still fully maintained.

## Developer Mode Installer (recommended)

> [!WARNING]
> You should have unblocked developer mode in some capacity before following the instructions below, most likely by setting your GBB flags to `0x8000`, `0x8090`, or `0x8091`.

Enter developer mode (either while enrolled or unenrolled) and boot into ChromeOS. Connect to WiFi, but don't log in. Open VT2 by pressing `Ctrl+Alt+F2 (Forward)` and log in as `root`. Run the following command:

```sh
bash <(curl -SLk bit.ly/al-murkmod)
```

Select the chromeOS milestone you want to install with murkmod. The script will then automatically download the correct recovery image, patch it, and install it to your device. Once the installation is complete, the system will reboot into a murkmod-patched rootfs. Continue to [Common Installation Steps](#common-installation-steps).

## Aurora 

Prerequisites: 
**WP disabled, GBB flags set**
<br>
Create an [Aurora](https://github.com/aerialitelabs/aurora) image and place a murkmod image built with the image_patcher.sh script into usr/share/images/recovery/

### fakemurk > murkmod upgrade

> [!WARNING]
> In order to use all of the features of murkmod, you **must** enable emergency revert during the installation of fakemurk.

> [!IMPORTANT]
> This method will only work with ChromeOS v105 (`og`) or v107 (`mercury`). If you wish to use a newer version (v117 `john` or v118 `pheonix`), you must use the methods above.

To install murkmod, simply spawn a root shell (option 1) from mush, and paste in the following command:

```sh
bash <(curl -SLk https://raw.githubusercontent.com/aerialitelabs/murkmodTempFix/main/murkmod.sh)
```

This command will download and install murkmod to your device. Once the installation is complete, you can start using murkmod by opening mush as usual.

> [!NOTE]
> Installing (or updating) fakemurk will set the password for the `chronos` user to `murkmod`.

> [!WARNING]
> If you get an error about a filesystem being readonly run `fsck -f $(rootdev)` then reboot.

## Common Installation Steps

~~If initial enrollment after installation fails after a long wait with an error about enrollment certificates, DON'T PANIC! This is normal. Perform an EC reset (`Refresh+Power`) and press space and then enter to *disable developer mode*. As soon as the screen backlight turns off, perform another EC reset and wait for the "ChromeOS is missing or damaged" screen to appear. Enter recovery mode (`Esc+Refresh+Power`) and press Ctrl+D and enter to enable developer mode, then enroll again. This time it should succeed.~~ Don't do this, something about making the rootfs RW-able has caused powerwashes to actually make murkmod unbootable if done. Instead, before continuing through oobe you should open vt2, login as root, and run `vpd -i RW_VPD -s check_enrollment=1; restart ui`. So long as your device secret and s/n haven't been tampered with, this should re-enroll you without the obscenely long delay. Also when policyedit is integrated, you'll have to change the asterisks in your policies.json open network configuration to the actual password, see [policy password tool](https://luphoria.com/netlog-policy-password-tool 

## The murkmod helper extension

murkmod also has an optional (recommended by rainestorme, not by me) helper extension that acts as a graphical abstraction over the top of mush, the murkmod developer shell. To install it:

- Download the repo from [here](https://codeload.github.com/aerialitelabs/murkmodtempfix/zip/refs/heads/main)
- Unzip the `helper` folder and place it anywhere you want on your Chromebook, ideally in your Downloads folder
- Go to `chrome://extensions` and enable developer mode, then select "Load unpacked" and select the `helper` folder
