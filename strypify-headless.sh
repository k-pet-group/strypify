#! /bin/bash

xvfb-run Strypify $* --no-sandbox --disable-setuid-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 3>&1 > /dev/null 2>&1
