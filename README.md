A program to take a Python file and output a PNG file with the image of that code pasted into Strype.

The latest version is available from the Releases on the right.

General Usage
===

You run the command supplying the required parameter `--file=foo.py` and it will write an image named something like strype-1234567890abcdef.png, and it will print that file name to file descriptor 3 (stdout unfortunately gets log spam from Electron that seems impossible to suppress).

The other available parameters are:
   - `--zoom=4.5` or whichever zoom level you'd like (affects how large and detailed the image is).  Default is `2.5`.

Windows Usage
===

Unzip the full zip and then either add that directory to your PATH or run from the directory like this:

    .\Strypify --file=foo.py

Mac Usage
===

On Mac Strypify compiles to a .app, so you must run (e.g. if you have put it in /Applications):

    /Applications/Strypify.app/Contents/MacOS/Strypify --file=foo.py

The app is not signed by default so each time you install/upgrade it, you may first need to run this command:

     xattr -dr com.apple.quarantine /Applications/Strypify.app

Then manually run it via the right/control-click menu to let MacOS be happy with you running an unsigned app.  We hope to add signing at some point in future.

Ubuntu Usage
===

You must disable the SUID functionality from the command line, like this:

    ./Strypify --file=foo.py --no-sandbox --disable-setuid-sandbox

If you are running headless (e.g. on a server) you will need to install the xvfb package and run like this:

    xvfb-run ./Strypify --file=foo.py --no-sandbox --disable-setuid-sandbox
