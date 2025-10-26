from PIL import Image, ImageChops
import math, operator, os

def rmsdiff(im1, im2):
    "Calculate the root-mean-square difference between two images"
    h = ImageChops.difference(im1, im2).histogram()
    sq = (value*((idx%256)**2) for idx, value in enumerate(h))
    sum_of_squares = sum(sq)
    rms = math.sqrt(sum_of_squares / (im1.size[0] * im1.size[1]))
    return rms


actual = os.environ['FILE']
expected = os.environ['EXPECTEDFILE']
print("Comparing images " + actual + " and " + expected)
im1 = Image.open(actual).convert("RGB")
im2 = Image.open(expected).convert("RGB")

im1_resized = im1.resize(im2.size, resample=Image.LANCZOS)

tolerance = 50  # Adjust RMS tolerance
diff = rmsdiff(im1_resized, im2)
print(f"RMS difference: {diff}")
if diff > tolerance:
    raise Exception(f"Image is too different from expected (tolerance {tolerance})")