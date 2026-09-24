from __future__ import annotations

import socket

import pytest

from engine.extraction.errors import InvalidSourceError
from engine.extraction.url_security import (
    validate_http_url_reference,
    validate_public_http_target,
)


@pytest.mark.parametrize(
    "url",
    [
        "http://224.0.0.251/",
        "http://[ff02::1]/",
        "http://[fec0::1]/",
    ],
)
def test_literal_non_public_unicast_addresses_are_rejected(url: str) -> None:
    with pytest.raises(InvalidSourceError):
        validate_http_url_reference(url)


@pytest.mark.parametrize(
    "resolved_ip",
    [
        "224.0.0.251",
        "ff02::1",
        "fec0::1",
    ],
)
def test_dns_non_public_unicast_answers_are_rejected(
    resolved_ip: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    family = socket.AF_INET6 if ":" in resolved_ip else socket.AF_INET

    def unsafe_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[object, ...]]]:
        if family == socket.AF_INET6:
            sockaddr: tuple[object, ...] = (resolved_ip, port, 0, 0)
        else:
            sockaddr = (resolved_ip, port)
        return [
            (
                family,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                sockaddr,
            )
        ]

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        unsafe_getaddrinfo,
    )

    with pytest.raises(InvalidSourceError):
        validate_public_http_target("https://fixture.example/rules")
