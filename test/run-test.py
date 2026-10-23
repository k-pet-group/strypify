import os
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

# Compares a generated image with its reference. Run with ACTUALFILE and EXPECTEDFILE set; exits non-zero if
# they differ too much.
#
# This is a pixel comparison (after a blur), rather than a perceptual hash: a hash squashes the image to a tiny
# size so that it mostly sees the overall layout, which let a render of entirely the wrong project pass while a
# near-identical wide image could fail.
#
# The references are renders from Linux (see update-expected-from-ci.sh). Layout is identical on every OS (the
# images come out the same size), but fonts are rasterised differently, so there are two levels of strictness:
#  - "exact" (the default on Linux): a render on the same platform is identical to the pixel, so the limits
#    leave only a little slack. This catches a single changed character or a 1 pixel layout shift.
#  - "loose" (the default elsewhere): blurs away the font differences, so only differences in layout or content
#    are caught -- the wrong project, a missing frame, a moved cursor, a wrong size.
# Set IMAGE_COMPARE=exact or IMAGE_COMPARE=loose to override.
#
# Two measures are used, because the mean over a large image would hide a small change (one changed character
# gives a mean of well under 0.1 on a tall image):
#  - the worst patch: the average difference within the most-different block. Exact mode, same platform: 0;
#    a changed character: 16+; a 1 pixel layout shift: around 20; the wrong project: around 95.
#    Loose mode, Windows/macOS vs the Linux reference: up to 23; the wrong project: 41; a moved cursor: 61.
#  - the mean difference over the whole image, as a backstop for a widespread but faint change.
#    Exact: 0 on the same platform. Loose, Windows/macOS vs Linux: up to 2.9; the wrong project: 8.9.
actual = os.environ['ACTUALFILE']
expected = os.environ['EXPECTEDFILE']

mode = os.environ.get('IMAGE_COMPARE') or ('exact' if sys.platform.startswith('linux') else 'loose')
if mode == 'exact':
    BLUR_RADIUS, BLOCK_SIZE, MAX_WORST_PATCH, MAX_MEAN_DIFFERENCE = 1.5, 16, 10, 0.3
elif mode == 'loose':
    BLUR_RADIUS, BLOCK_SIZE, MAX_WORST_PATCH, MAX_MEAN_DIFFERENCE = 3, 32, 30, 4
else:
    sys.exit(f"Unknown IMAGE_COMPARE mode: {mode}")
MAX_SIZE_DIFFERENCE = 2       # pixels, in each dimension

a = Image.open(actual).convert('L')
e = Image.open(expected).convert('L')
print(f"Comparing ({mode}); sizes actual/expected:", a.size, e.size)

if abs(a.width - e.width) > MAX_SIZE_DIFFERENCE or abs(a.height - e.height) > MAX_SIZE_DIFFERENCE:
    print(f"Image sizes differ by more than {MAX_SIZE_DIFFERENCE} pixels")
    sys.exit(1)

# Compare the part they have in common:
width, height = min(a.width, e.width), min(a.height, e.height)
a = a.crop((0, 0, width, height)).filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
e = e.crop((0, 0, width, height)).filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
diff = ImageChops.difference(a, e)
mean = ImageStat.Stat(diff).mean[0]
# Shrinking by box-averaging gives each block's mean difference, so the maximum is the worst patch:
blocks = diff.resize((max(1, width // BLOCK_SIZE), max(1, height // BLOCK_SIZE)), Image.BOX)
worst_patch = blocks.getextrema()[1]

print(f"Worst {BLOCK_SIZE}x{BLOCK_SIZE} patch difference: {worst_patch} (max {MAX_WORST_PATCH}), "
      f"mean difference: {mean:.2f} (max {MAX_MEAN_DIFFERENCE})")

if worst_patch <= MAX_WORST_PATCH and mean <= MAX_MEAN_DIFFERENCE:
    print("Images match")
else:
    print("Images differ!")
    sys.exit(1)
