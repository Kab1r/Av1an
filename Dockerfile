FROM archlinux:base-devel AS base

RUN pacman -Syu --noconfirm

# Install dependancies needed by all steps including runtime step
RUN pacman -S --noconfirm --needed ffmpeg vapoursynth ffms2 libvpx mkvtoolnix-cli svt-av1 vapoursynth-plugin-lsmashsource vmaf tesseract-data-eng

FROM base AS build-aur

RUN pacman -S --noconfirm --needed git sudo cmake doxygen graphviz yasm && \
    useradd builduser -m && \
    passwd -d builduser && \
    printf 'builduser ALL=(ALL) ALL\n' | tee -a /etc/sudoers && \
    sed -i -e "s/-march=x86-64 -mtune=generic -O2/-march=native -mtune=generic -O3/g" /etc/makepkg.conf && \
    sudo -u builduser bash -c ' \
        cd ~ && \
        git clone https://aur.archlinux.org/aom-git.git && \
        cd aom-git && \
        makepkg -s \
    '

FROM base AS build-base

# Install dependancies needed by build steps
RUN pacman -S --noconfirm --needed rust clang nasm git

RUN RUSTFLAGS="-C target-cpu=native -C opt-level=3" cargo install cargo-chef
WORKDIR /tmp/Av1an


FROM build-base AS planner

COPY . .
RUN RUSTFLAGS="-C target-cpu=native -C opt-level=3" cargo chef prepare


FROM build-base AS build

COPY --from=planner /tmp/Av1an/recipe.json recipe.json
RUN RUSTFLAGS="-C target-cpu=native -C opt-level=3" cargo chef cook --release

# Compile rav1e from git, as archlinux is still on rav1e 0.4
RUN git clone https://github.com/xiph/rav1e && \
    cd rav1e && \
    RUSTFLAGS="-C target-cpu=native -C opt-level=3" cargo build --release && \
    strip ./target/release/rav1e && \
    mv ./target/release/rav1e /usr/local/bin && \
    cd .. && rm -rf ./rav1e

# Build av1an
COPY . /tmp/Av1an

RUN RUSTFLAGS="-C target-cpu=native -C opt-level=3" cargo build --release && \
    mv ./target/release/av1an /usr/local/bin && \
    cd .. && rm -rf ./Av1an


FROM base AS runtime

COPY --from=build-aur /home/builduser/aom-git/aom-git-*.pkg.tar.zst /aom-git.pkg.tar.zst
RUN pacman -Rd --nodeps --noconfirm aom && \
    pacman -U --noconfirm /aom-git.pkg.tar.zst && \
    rm /aom-git.pkg.tar.zst

ENV MPLCONFIGDIR="/home/app_user/"

COPY --from=build /usr/local/bin/rav1e /usr/local/bin/rav1e
COPY --from=build /usr/local/bin/av1an /usr/local/bin/av1an

# Create user
RUN useradd -ms /bin/bash app_user
USER app_user

VOLUME ["/videos"]
WORKDIR /videos

ENTRYPOINT [ "/usr/local/bin/av1an" ]
