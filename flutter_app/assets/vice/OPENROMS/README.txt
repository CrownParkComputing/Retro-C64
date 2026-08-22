Open ROMs -- a free, open-source replacement for the Commodore C64 ROMs.

These three files are NOT Commodore's. They are the MEGA65 team's Open ROMs
project: a clean-room BASIC, KERNAL and character set written from scratch.

    kernal    open-roms kernal_generic.rom   8 KB
    basic     open-roms basic_generic.rom    8 KB
    chargen   open-roms chargen_openroms.rom 4 KB

Source: https://github.com/MEGA65/open-roms

LICENCE. GNU Lesser General Public License v3 or later -- see COPYING.LESSER,
with COPYING for the GPL v3 text it builds on, and LICENSE.txt for the
project's own copyright notice. Copyright Paul Gardner-Stephen (2019) and
Roman Standzikowski / FeralChild64 (2019-2021). Some BASIC routines in the
project are MIT-licensed, Copyright Microsoft Corporation.

It is the LESSER GPL, not the GPL. The repository carries both texts because
that is how the LGPL is written -- as an additional permission on top of the
GPL v3 -- and reading only COPYING gets the licence wrong.

The build these came from identifies itself on screen as
"OPEN ROMS GENERIC BUILD / RELEASE DEV.210823.FC.1".

They are here so the app can show a working C64 out of the box, with nothing
for the user to supply and nobody's copyright infringed. They are NOT a
replacement for the real thing: Open ROMs is an ongoing project and does not
implement every KERNAL routine -- its BASIC has no variables, no FOR/NEXT and
no CHR$ -- so commercial software written against the original ROMs will not
generally run. For that, the user supplies Commodore's own ROMs, which the
app asks for separately and never ships.
