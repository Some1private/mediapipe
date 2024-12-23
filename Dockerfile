# Copyright 2019 The MediaPipe Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ubuntu:22.04

MAINTAINER <mediapipe@google.com>

WORKDIR /io
WORKDIR /mediapipe

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies first
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc g++ \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        wget \
        unzip \
        nodejs \
        npm \
        python3-dev \
        python3-pip \
        cmake \
        pkg-config \
        lsb-release \
        software-properties-common \
        gnupg \
        libgtk-3-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libxvidcore-dev \
        libx264-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        gfortran \
        openexr \
        libatlas-base-dev \
        python3-numpy \
        libtbb2 \
        libtbb-dev \
        libdc1394-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install LLVM
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 16 && \
    ln -sf /usr/bin/clang-16 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-16 /usr/bin/clang++ && \
    ln -sf /usr/bin/clang-format-16 /usr/bin/clang-format && \
    rm llvm.sh

# Install OpenCV 3.4.16
RUN cd /tmp && \
    wget -q https://github.com/opencv/opencv/archive/3.4.16.zip -O opencv.zip && \
    wget -q https://github.com/opencv/opencv_contrib/archive/3.4.16.zip -O opencv_contrib.zip && \
    unzip -q opencv.zip && \
    unzip -q opencv_contrib.zip && \
    mv opencv-3.4.16 opencv && \
    mv opencv_contrib-3.4.16 opencv_contrib && \
    mkdir -p opencv/build && \
    cd opencv/build && \
    cmake -D CMAKE_BUILD_TYPE=RELEASE \
          -D CMAKE_INSTALL_PREFIX=/usr/local \
          -D INSTALL_PYTHON_EXAMPLES=OFF \
          -D INSTALL_C_EXAMPLES=OFF \
          -D OPENCV_ENABLE_NONFREE=ON \
          -D OPENCV_EXTRA_MODULES_PATH=/tmp/opencv_contrib/modules \
          -D PYTHON_EXECUTABLE=/usr/bin/python3 \
          -D BUILD_EXAMPLES=OFF \
          -D PYTHON_DEFAULT_EXECUTABLE=/usr/bin/python3 \
          -D BUILD_opencv_python3=ON \
          -D PYTHON3_EXECUTABLE=/usr/bin/python3 \
          -D PYTHON3_INCLUDE_DIR=/usr/include/python3.10 \
          -D PYTHON3_PACKAGES_PATH=/usr/lib/python3/dist-packages \
          .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd /tmp && \
    rm -rf opencv* && \
    rm -rf *.zip

# Install additional dependencies
RUN apt-get update && apt-get install -y \
        mesa-common-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        mesa-utils \
        openjdk-8-jdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade setuptools
RUN pip3 install wheel
RUN pip3 install future
RUN pip3 install absl-py "numpy<2" jax[cpu] opencv-python==3.4.17.61 protobuf==3.20.1
RUN pip3 install six==1.14.0
RUN pip3 install tensorflow
RUN pip3 install tf_slim

RUN ln -s /usr/bin/python3 /usr/bin/python

# Install bazel
ARG BAZEL_VERSION=6.5.0
RUN mkdir /bazel && \
    wget --no-check-certificate -O /bazel/installer.sh "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/b\
azel-${BAZEL_VERSION}-installer-linux-x86_64.sh" && \
    wget --no-check-certificate -O  /bazel/LICENSE.txt "https://raw.githubusercontent.com/bazelbuild/bazel/master/LICENSE" && \
    chmod +x /bazel/installer.sh && \
    /bazel/installer.sh  && \
    rm -f /bazel/installer.sh

COPY . /mediapipe/

# Set default build configuration for AutoFlip
ENV MEDIAPIPE_DISABLE_GPU=1

# Configure Bazel cache directory and settings
ENV BAZEL_CACHE=/root/.cache/bazel
RUN mkdir -p $BAZEL_CACHE
COPY .bazelrc /mediapipe/.bazelrc
RUN echo "build --disk_cache=$BAZEL_CACHE" >> /mediapipe/.bazelrc && \
    echo "build --repository_cache=$BAZEL_CACHE/repos" >> /mediapipe/.bazelrc && \
    echo "build --experimental_repository_cache_hardlinks" >> /mediapipe/.bazelrc && \
    echo "build --experimental_guard_against_concurrent_changes" >> /mediapipe/.bazelrc

# Build AutoFlip by default
RUN --mount=type=cache,target=/root/.cache/bazel,id=bazel_cache \
    --mount=type=cache,target=/root/.cache/pip,id=pip_cache \
    BAZEL_CXXOPTS="-std=c++17" \
    bazel build -c opt \
    --define MEDIAPIPE_DISABLE_GPU=1 \
    --define=XNNPACK_ENABLE_ASSEMBLY=false \
    --define=XNNPACK_X86_FLAGS="-mno-avx512f -mno-avx512cd -mno-avx512er -mno-avx512pf -mno-avx512bw -mno-avx512dq -mno-avx512vl -mno-avx512ifma -mno-avx512vbmi -mno-avxvnni" \
    --copt=-march=x86-64-v2 \
    --copt=-mtune=generic \
    --copt=-fvisibility=hidden \
    --copt=-Wno-sign-compare \
    --copt=-fno-strict-aliasing \
    --host_copt=-fPIC \
    --linkopt=-fPIC \
    --compilation_mode=opt \
    --define=use_fast_cpp_protos=true \
    --define=allow_oversize_protos=true \
    --define=grpc_no_ares=true \
    --experimental_repo_remote_exec \
    --incompatible_enable_cc_toolchain_resolution \
    --features=-layering_check \
    --keep_going \
    //mediapipe/examples/desktop/autoflip:run_autoflip
