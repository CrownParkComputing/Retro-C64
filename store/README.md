# Store assets

## Screenshots

Raw device captures go in `screenshots-raw/`, one PNG per screen, named so
they sort into the order you want them shown (`1-library.png`, ...). Then:

    tools/make-store-screenshots.py

which writes exactly-sized, alpha-free copies into `screenshots/<target>/`.

Do not upload the raw captures. App Store Connect rejects anything whose
dimensions are not exactly one of the sizes it lists, and rejects images with
an alpha channel; a device capture is neither. This iPad shoots 2388x1668 and
Apple asks for 2752x2064, so the tool scales to fit and pads on the app's own
background rather than stretching, which would distort the picture visibly.

**iPhone screenshots have to be shot on an iPhone.** Padding a 4:3 iPad screen
into a 2.2:1 iPhone frame leaves bars down both sides and looks exactly like
what it is. If the app ships iPhone support (`UIDeviceFamily` is `[1, 2]`, so
it currently claims to), that set is still needed.

## Icons

`tools/make-ios-icons.py` regenerates every iOS icon from
`flutter_app/assets/images/retro_recomp_logo.png` and the Android plate
colour. Run it after changing the logo. See the note in that file about why
the artwork is recomposed rather than copied from the Android PNGs.
