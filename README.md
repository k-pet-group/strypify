A program to take a Python file and output a PNG file with the image of that code pasted into Strype.

On Windows this compiles to an EXE which is clear how to execute from the command line.  On Mac it compiles to a .app, so you must run:

    /Applications/Strypify.app/Contents/MacOS/Strypify

The required argument is --file=foo.py, and an optional argument is --zoom=1 (default is 2.5).  The equals are required.  So for example:

    /Applications/Strypify.app/Contents/MacOS/Strypify --zoom=3 --file=myprog.py

The output file will be generated in the current directory, named strype-*hash*.png where the hash is the md5 hash of the source code.  If such a file already exists it will deliberately not be overwritten (delete the file first if you want to replace it).

The app is not signed by default so each time you install/upgrade it, you may need to run it manually via the right/control-click menu to let MacOS be happy with you running an unsigned app.