"""Process-wide initialization shared by API, admin and worker adapters."""

from threading import Lock

import firebase_admin


_initialization_lock = Lock()


def initialize_firebase():
    # get_app and initialize_app are individually synchronized by the SDK,
    # but their check-then-create sequence must also be atomic for our callers.
    # Do not cache failures: corrected credentials can be retried immediately.
    with _initialization_lock:
        try:
            return firebase_admin.get_app()
        except ValueError:
            return firebase_admin.initialize_app()
