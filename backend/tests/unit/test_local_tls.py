"""Local HTTPS keeps the production cookie policy without committing a key."""

import importlib.util
from ipaddress import ip_address
from pathlib import Path
import stat

from cryptography import x509


def tls_module():
    path = Path(__file__).resolve().parents[3] / 'deploy/local/create_tls.py'
    spec = importlib.util.spec_from_file_location('nowave_local_tls', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_local_certificate_covers_loopback_and_keeps_private_key_restricted(tmp_path):
    tls_module().ensure_certificate(tmp_path)
    certificate = x509.load_pem_x509_certificate((tmp_path / 'localhost.crt').read_bytes())
    names = certificate.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    assert names.get_values_for_type(x509.DNSName) == ['localhost']
    assert set(names.get_values_for_type(x509.IPAddress)) == {
        ip_address('127.0.0.1'), ip_address('::1'),
    }
    assert stat.S_IMODE((tmp_path / 'localhost.key').stat().st_mode) == 0o600


def test_restarting_preserves_certificate_but_recovers_a_broken_key(tmp_path):
    module = tls_module()
    module.ensure_certificate(tmp_path)
    certificate = (tmp_path / 'localhost.crt').read_bytes()
    module.ensure_certificate(tmp_path)
    assert (tmp_path / 'localhost.crt').read_bytes() == certificate
    (tmp_path / 'localhost.key').write_text('invalid key')
    module.ensure_certificate(tmp_path)
    assert (tmp_path / 'localhost.crt').read_bytes() != certificate
