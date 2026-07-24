# Current Git Bundle — Third-Party Notices

## Git 2.55.0

Git is distributed under the GNU General Public License, version 2 only.
The complete license text is included as `Git-GPL-2.0.txt`.

The exact corresponding source archive used for this build is:

- https://www.kernel.org/pub/software/scm/git/git-2.55.0.tar.xz
- SHA-256: `457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357`

The reproducible build options and target are recorded in
`GitBundle.lock.json` and `GitBundle.sbom.cdx.json`.

## Git LFS 3.7.1

Git LFS is distributed under the MIT License. The complete license text
is included as `Git-LFS-MIT.txt`.

The exact arm64 binary archive used for this build is:

- https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-darwin-arm64-v3.7.1.zip
- SHA-256: `76260fb34f4ee622ff0a66b857e5954aa49c7e343a92e57a1ec4a760618c94b2`

Corresponding source:

- https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-v3.7.1.tar.gz
- SHA-256: `8f56058622edfea1d111e50e9844ef2f5ce670b2dbe4d55d48e765c943af4351`

## Apple system libraries

The Git executables dynamically use libraries and frameworks supplied by
macOS, including CoreServices, CoreFoundation, libSystem, libcurl, libexpat,
libiconv, and libz. No Homebrew or `/usr/local` dynamic library is permitted
by the bundle verification script.
