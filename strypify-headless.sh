#! /bin/bash

# The normal path discards all of Strypify's stdout/stderr (the result is passed back on fd 3),
# but --version prints its result on stdout, so let that one through.
case " $* " in
  *" --version "*|*" -v "*)
    xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 2>/dev/null
    exit $?
    ;;
esac

xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 3>&1 > /dev/null 2>&1
