FROM ubuntu:22.04

# System and user configuration
ENV USER staruser
ENV UID 1000
ENV GID 1000
ENV USER_SCRIPTS /home/${USER}/.local/bin
ENV PATH="${USER_SCRIPTS}:${PATH}"

# Game and server variables
ENV STAR_APPID 3809400
ENV SERVER_SHUTDOWN_TIMEOUT 30
ENV STEAM_DIR /steam
ENV GAME_DIR /starrupture
ENV SCRIPTS_DIR /scripts

# Wine configuration
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH ${GAME_DIR}
ENV STEAM_COMPAT_DATA_PATH ${GAME_DIR}/steamapps/compatdata/${STAR_APPID}
ENV WINEDEBUG -all
ENV WINEARCH win64
ENV WINEPREFIX ${STEAM_COMPAT_DATA_PATH}/pfx
ENV DISPLAY :99
ENV XDG_RUNTIME_DIR /tmp

# Log file locations
ENV SERVER_LOG ${GAME_DIR}/StarRupture/Saved/Logs/StarRupture.log

# Locale configuration
ENV LANG en_US.UTF-8

# Add i386 architecture for Steam (32-bit app)
RUN dpkg --add-architecture i386

# Install all required packages in a single layer
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # General utilities
    wget curl jq iproute2 locales procps software-properties-common \
    dbus htop vim unzip \
    # Wine dependencies
    lib32gcc-s1 lib32stdc++6 libasound2 libc6-i386 libpulse0 xvfb \
    winetricks libgcc-11-dev gcc-multilib g++-multilib libncurses5:i386 \
    libncurses6:i386 cabextract \
    # Add WineHQ repository and install
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    # Configure winetricks
    && wget -q -O /usr/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x /usr/bin/winetricks \
    # Configure locale
    && locale-gen en_US.UTF-8 \
    # Cleanup to reduce image size
    && apt-get -y autoremove \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create user and setup directory structure
RUN set -ex \
    # Create user and group
    && groupadd --gid ${GID} ${USER} \
    && useradd --create-home --shell /bin/bash --uid ${UID} --gid ${GID} ${USER} \
    # Create required directories
    && mkdir -p ${USER_SCRIPTS} ${GAME_DIR} ${SCRIPTS_DIR} ${STEAM_DIR} \
    ${STEAM_COMPAT_DATA_PATH} ${WINEPREFIX} /tmp/.X11-unix \
    # Set permissions
    && chmod 1777 /tmp /tmp/.X11-unix \
    && touch /etc/fstab \
    && chown -R ${USER}:${USER} /home/${USER} ${STEAM_DIR} ${SCRIPTS_DIR} \
    ${WINEPREFIX} ${GAME_DIR}

# Switch to non-root user for remaining operations
USER ${USER}

# Set up user environment and download SteamCMD
RUN set -ex \
    # Configure shell aliases
    && echo "alias ll='ls -alF'" >> /home/${USER}/.bashrc \
    && echo "export PATH='$PATH:${USER_SCRIPTS}'" >> /home/${USER}/.bashrc \
    # Download SteamCMD
    && cd ${STEAM_DIR} \
    && curl "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

# Copy scripts and entrypoint
COPY --chown=${USER} --chmod=755 ./scripts ${SCRIPTS_DIR}
COPY --chown=${USER} --chmod=755 ./entrypoint.sh /entrypoint.sh

# Create CLI symlinks for convenience
RUN ln -sf ${SCRIPTS_DIR}/start.sh ${USER_SCRIPTS}/star-start \
    && ln -sf ${SCRIPTS_DIR}/stop.sh ${USER_SCRIPTS}/star-stop \
    && ln -sf ${SCRIPTS_DIR}/update.sh ${USER_SCRIPTS}/star-update \
    && ln -sf ${SCRIPTS_DIR}/status.sh ${USER_SCRIPTS}/star-status

WORKDIR ${GAME_DIR}
ENTRYPOINT ["/entrypoint.sh"]
