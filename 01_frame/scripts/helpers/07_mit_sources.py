"""Cache the reviewed original MIT Election Data and Science Lab returns."""

import hashlib
import urllib.error
import urllib.request
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import NamedTuple


class Source(NamedTuple):
    local_name: str
    original_name: str
    doi: str
    version: str
    file_id: int
    size: int
    md5: str
    sha256: str


# File IDs, byte lengths and MD5s come from the specified Harvard Dataverse
# versions. SHA-256s were computed on the original files matching those MD5s.
PRESIDENT = Source(
    "1976-2024-president.csv", "1976-2024-president.csv", "42MVDX", "10.1",
    13887042, 514108, "405af83db7625cb35d8c19a5ebe029ff",
    "9936410a6dd4ecc8be7fe202c6dff5b5f8fee59d88f35ab542ed12879941dcb7",
)
HOUSE = Source(
    "1976-2024-house.csv", "1976-2024-house.tab", "IG0UN2", "15.0",
    13592823, 4156562, "a9566ac393913a1af343284e837c17bb",
    "76eec42483ee9f0fc5cf6e377442c783d1ae6eefa929729fd6561a69bab47f2a",
)


def obtain(directory, source):
    path = directory / source.local_name
    page = ("https://dataverse.harvard.edu/dataset.xhtml?"
            f"persistentId=doi:10.7910/DVN/{source.doi}&version={source.version}")
    manual = (
        f"Open {page}, select {source.original_name} and download Original Format. "
        "Complete the publisher's guestbook if requested. Extract the original "
        f"file if delivered in a ZIP, save its unchanged bytes at {path}, and rerun."
    )
    cached = path.exists()
    if cached:
        data = path.read_bytes()
    else:
        url = f"https://dataverse.harvard.edu/api/access/datafile/{source.file_id}?format=original"
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                data = response.read(source.size + 1)
        except (urllib.error.URLError, OSError) as error:
            raise RuntimeError(f"Harvard Dataverse download failed ({error}). {manual}") from error

    if (len(data) != source.size or hashlib.sha256(data).hexdigest() != source.sha256 or
            hashlib.md5(data, usedforsecurity=False).hexdigest() != source.md5):
        origin = str(path) if cached else "Harvard Dataverse response"
        raise ValueError(f"{origin} differs from the reviewed original for {source.local_name}. {manual}")

    if not cached:
        with TemporaryDirectory(dir=directory) as temporary:
            staged = Path(temporary) / source.local_name
            staged.write_bytes(data)
            staged.replace(path)
    return path


def obtain_mit_sources(input_dir):
    """Return verified original CSV paths in presidential, House order."""
    directory = Path(input_dir) / "07_area_returns"
    directory.mkdir(parents=True, exist_ok=True)
    return obtain(directory, PRESIDENT), obtain(directory, HOUSE)
