"""Create a persistent certificate for the local HTTPS frontend only."""

from datetime import UTC, datetime, timedelta
from ipaddress import ip_address
from pathlib import Path
import os

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


def ensure_certificate(directory: Path, *, owner=None):
    directory.mkdir(parents=True, exist_ok=True)
    certificate = directory / "localhost.crt"
    private_key = directory / "localhost.key"
    now = datetime.now(UTC)
    try:
        current = x509.load_pem_x509_certificate(certificate.read_bytes())
        key = serialization.load_pem_private_key(private_key.read_bytes(), password=None)
        reusable = (
            current.not_valid_before_utc <= now
            and current.not_valid_after_utc > now + timedelta(days=1)
            and current.public_key().public_numbers() == key.public_key().public_numbers()
        )
    except (OSError, ValueError):
        reusable = False
    if not reusable:
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
        current = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=5))
            .not_valid_after(now + timedelta(days=365))
            .add_extension(x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.IPAddress(ip_address("127.0.0.1")),
                x509.IPAddress(ip_address("::1")),
            ]), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .sign(key, hashes.SHA256())
        )
        # Create private material with restrictive permissions from the start.
        descriptor = os.open(private_key, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(key.private_bytes(
                serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            ))
        certificate.write_bytes(current.public_bytes(serialization.Encoding.PEM))
    private_key.chmod(0o600)
    certificate.chmod(0o644)
    if owner is not None:
        for path in (certificate, private_key):
            os.chown(path, *owner)


if __name__ == "__main__":
    ensure_certificate(Path("/certificates"), owner=(101, 101))
