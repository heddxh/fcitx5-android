#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly FCITX5_MOZC_DIR="${ROOT_DIR}/plugin/mozc/src/main/cpp/fcitx5-mozc"
readonly MOZC_DIR="${FCITX5_MOZC_DIR}/mozc"
readonly DICTIONARY_DIR="${MOZC_DIR}/src/data/dictionary_oss"
readonly OUTPUT_DIR="${ROOT_DIR}/plugin/mozc/build/mozc"
readonly MERGE_UT_COMMIT="15c1c64502b43e31d328012860376c03c3eaf633"
readonly JAWIKI_INDEX="jawiki-20260601-pages-articles-multistream-index.txt.bz2"
readonly JAWIKI_INDEX_B2="cd4c02ee67d98084b6e4909eea77ca464d3cca838595538c5219710927aa42630fa67110f45297252c11f8e8c84d5a3c346a378b848d86ca14b4eb84505c1f74"

if [[ ! -f "${MOZC_DIR}/src/BUILD.bazel" ]]; then
    echo "Mozc sources are missing. Initialize the fcitx5-mozc submodule first." >&2
    exit 1
fi

if ! git -C "${MOZC_DIR}" diff --quiet -- src/data/dictionary_oss/dictionary00.txt; then
    echo "dictionary00.txt has local changes; refusing to overwrite them." >&2
    exit 1
fi
if ! git -C "${FCITX5_MOZC_DIR}/protobuf" diff --quiet; then
    echo "The protobuf submodule has local changes; refusing to patch it." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/mozc-ut.XXXXXXXX")"
PROTOBUF_PATCHED=false
cleanup() {
    git -C "${MOZC_DIR}" checkout -- src/data/dictionary_oss/dictionary00.txt
    if [[ "${PROTOBUF_PATCHED}" == true ]]; then
        git -C "${FCITX5_MOZC_DIR}" apply --reverse --directory=protobuf patches/protobuf.patch
    fi
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

git clone --quiet --filter=blob:none https://github.com/utuhiro78/merge-ut-dictionaries.git "${WORK_DIR}/merge-ut-dictionaries"
git -C "${WORK_DIR}/merge-ut-dictionaries" checkout --quiet "${MERGE_UT_COMMIT}"
git -C "${WORK_DIR}/merge-ut-dictionaries" apply "${ROOT_DIR}/.github/mozc-ut/merge-local-sources.patch"

download_dictionary() {
    local name="$1"
    local commit="$2"
    local sha256="$3"
    local archive="${WORK_DIR}/mozcdic-ut-${name}.txt.bz2"

    curl --fail --location --retry 3 --silent --show-error \
        "https://raw.githubusercontent.com/utuhiro78/mozcdic-ut-${name}/${commit}/mozcdic-ut-${name}.txt.bz2" \
        --output "${archive}"
    echo "${sha256}  ${archive}" | sha256sum --check
    bzip2 --decompress --stdout "${archive}" >> "${WORK_DIR}/mozcdic-ut.txt"
}

download_dictionary \
    jawiki \
    b50cabaecaf32c03d102db55fc5d0b98e334ec9e \
    4311b905af9ca9a226a83d9dc0014fa48116f251e7b8432448e192444b31c3d7
download_dictionary \
    place-names \
    6f9d9bda14f0bd2c10c1563d2aed9150ea95095c \
    e8369ce4c759e568cd5df1a286851761cd33f5adbd414fab499e1e03b55735ec
download_dictionary \
    sudachidict \
    7def3da408b1854801bd5b559273f9fb8001ef5b \
    696e745b7f7e9e202497421cee048de058d85b79cc79edc31c4f89b7b33675d9

curl --fail --location --retry 3 --silent --show-error \
    "https://dumps.wikimedia.org/jawiki/20260601/${JAWIKI_INDEX}" \
    --output "${WORK_DIR}/${JAWIKI_INDEX}"
echo "${JAWIKI_INDEX_B2}  ${WORK_DIR}/${JAWIKI_INDEX}" | b2sum --check

readonly INPUT_ENTRIES="$(wc --lines < "${WORK_DIR}/mozcdic-ut.txt")"
python "${WORK_DIR}/merge-ut-dictionaries/src/merge/merge_dictionaries.py" \
    "${WORK_DIR}/mozcdic-ut.txt" \
    "${DICTIONARY_DIR}" \
    "${WORK_DIR}/${JAWIKI_INDEX}"
readonly MERGED_ENTRIES="$(wc --lines < "${WORK_DIR}/mozcdic-ut.txt")"

cat "${WORK_DIR}/mozcdic-ut.txt" >> "${DICTIONARY_DIR}/dictionary00.txt"

git -C "${FCITX5_MOZC_DIR}" apply --directory=protobuf patches/protobuf.patch
PROTOBUF_PATCHED=true

(
    cd "${MOZC_DIR}/src"
    bazel build \
        --config oss_linux \
        --host_cxxopt=-Wno-uninitialized \
        //data_manager/oss:mozc_data.inc
)

mkdir -p "${OUTPUT_DIR}"
cp "${MOZC_DIR}/src/bazel-bin/data_manager/oss/mozc_data.inc" "${OUTPUT_DIR}/"
cp "${MOZC_DIR}/src/bazel-bin/data_manager/oss/mozc.data" "${OUTPUT_DIR}/"

{
    echo "input_entries=${INPUT_ENTRIES}"
    echo "merged_entries=${MERGED_ENTRIES}"
    stat --printf='mozc_data_inc_bytes=%s\n' "${OUTPUT_DIR}/mozc_data.inc"
    stat --printf='mozc_data_bytes=%s\n' "${OUTPUT_DIR}/mozc.data"
    echo "mozc_data_sha256=$(sha256sum "${OUTPUT_DIR}/mozc_data.inc" | cut --delimiter=' ' --fields=1)"
} | tee "${OUTPUT_DIR}/mozc-ut-data.txt"
