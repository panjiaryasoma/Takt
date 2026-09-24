"""Application-level URL safety checks for native HTTP(S) ingestion.

These checks are defense-in-depth only. They reject obviously unsafe URL
references and hostnames that currently resolve to non-public addresses before
httpx is allowed to connect. Network-level egress controls remain the
authoritative production defense against DNS rebinding and routing races.
"""

from __future__ import annotations

import socket
from ipaddress import IPv4Address, IPv6Address, ip_address
from urllib.parse import urlsplit

from engine.extraction.errors import InvalidSourceError, SourceFetchError


def _normalized_ip(value: str) -> IPv4Address | IPv6Address:
    """Parse a socket address, normalizing scoped/mapped IPv6 when useful."""

    raw = value.split("%", 1)[0]
    parsed = ip_address(raw)
    if isinstance(parsed, IPv6Address) and parsed.ipv4_mapped is not None:
        return parsed.ipv4_mapped
    return parsed


def _reject_non_public_ip(value: str, *, source_ref: str, resolved: bool) -> None:
    parsed = _normalized_ip(value)
    unsafe = (
        not parsed.is_global
        or parsed.is_multicast
        or parsed.is_unspecified
        or parsed.is_loopback
        or parsed.is_link_local
        or parsed.is_reserved
        or (isinstance(parsed, IPv6Address) and parsed.is_site_local)
    )
    if not unsafe:
        return

    if resolved:
        message = "source hostname resolved to a non-public IP address"
    else:
        message = "non-public IP source URLs are not allowed"
    raise InvalidSourceError(message, source_ref=source_ref)


def validate_http_url_reference(url: str) -> tuple[str, int, bool]:
    """Validate HTTP(S) syntax and literal-IP safety without DNS resolution.

    Returns ``(hostname, port, is_literal_ip)`` for callers that need to apply
    a DNS-resolution guard immediately before connecting.
    """

    if not isinstance(url, str) or not url.strip():
        raise InvalidSourceError("source URL must be a non-empty string")

    try:
        parsed = urlsplit(url)
        hostname = parsed.hostname
        explicit_port = parsed.port
    except (TypeError, ValueError) as exc:
        raise InvalidSourceError("source URL is malformed", source_ref=str(url)) from exc

    if parsed.scheme not in {"http", "https"}:
        raise InvalidSourceError(
            "source URL must use http or https",
            source_ref=url,
        )
    if not hostname:
        raise InvalidSourceError("source URL must include a hostname", source_ref=url)
    if parsed.username is not None or parsed.password is not None:
        raise InvalidSourceError(
            "source URL must not contain embedded credentials",
            source_ref=url,
        )

    hostname = hostname.rstrip(".").lower()
    if hostname == "localhost" or hostname.endswith(".localhost"):
        raise InvalidSourceError("local source URLs are not allowed", source_ref=url)

    default_port = 443 if parsed.scheme == "https" else 80
    port = explicit_port if explicit_port is not None else default_port

    try:
        _normalized_ip(hostname)
    except ValueError:
        return hostname, port, False

    _reject_non_public_ip(hostname, source_ref=url, resolved=False)
    return hostname, port, True


def validate_public_http_target(url: str) -> None:
    """Reject a URL when any current DNS answer is not globally routable.

    This intentionally uses an all-or-nothing policy: if a hostname resolves to
    both public and private/special addresses, the target is rejected rather
    than hoping the HTTP client chooses the public answer.
    """

    hostname, port, is_literal_ip = validate_http_url_reference(url)
    if is_literal_ip:
        return

    try:
        answers = socket.getaddrinfo(
            hostname,
            port,
            family=socket.AF_UNSPEC,
            type=socket.SOCK_STREAM,
        )
    except (socket.gaierror, OSError) as exc:
        raise SourceFetchError(
            "source hostname could not be resolved",
            source_ref=url,
        ) from exc

    if not answers:
        raise SourceFetchError(
            "source hostname did not resolve to an address",
            source_ref=url,
        )

    saw_address = False
    for answer in answers:
        sockaddr = answer[4]
        if not sockaddr:
            continue
        raw_ip = sockaddr[0]
        try:
            _reject_non_public_ip(raw_ip, source_ref=url, resolved=True)
        except ValueError as exc:
            raise SourceFetchError(
                "source hostname resolved to an invalid IP address",
                source_ref=url,
            ) from exc
        saw_address = True

    if not saw_address:
        raise SourceFetchError(
            "source hostname did not resolve to a usable address",
            source_ref=url,
        )
