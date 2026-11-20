"""Соединение с офисным сервером (аналог NetworkClient.swift).

* Адрес задан вручную (`host` или `host:port`) — подключаемся сразу.
* Иначе ищем сервер через mDNS/Bonjour (`_homeview._tcp`), библиотека zeroconf.
* Разрыв — переподключение через 2, 4, 8 … 30 секунд.
"""

from __future__ import annotations

import ipaddress
import logging
import threading
from typing import Callable

from PySide6.QtCore import QObject, QTimer, QUrl, Signal
from PySide6.QtNetwork import QAbstractSocket
from PySide6.QtWebSockets import QWebSocket, QWebSocketProtocol

from . import protocol

log = logging.getLogger(__name__)

DISCOVERY_WARN_SECONDS = 12


def parse_address(address: str) -> tuple[str, int]:
    address = address.strip()
    for prefix in ("ws://", "http://"):
        if address.startswith(prefix):
            address = address[len(prefix):]
    address = address.rstrip("/")
    if address.startswith("["):  # [IPv6]:port
        host, _, rest = address[1:].partition("]")
        port = rest.lstrip(":")
        return host, int(port) if port.isdigit() else protocol.DEFAULT_PORT
    if address.count(":") == 1:
        host, port = address.split(":")
        return host, int(port) if port.isdigit() else protocol.DEFAULT_PORT
    return address, protocol.DEFAULT_PORT


def ws_url(host: str, port: int) -> QUrl:
    try:
        if ipaddress.ip_address(host).version == 6:
            host = f"[{host}]"
    except ValueError:
        pass
    return QUrl(f"ws://{host}:{port}/")


class _Discovery:
    """mDNS-поиск в фоновом потоке zeroconf; результат передаётся через сигнал Qt."""

    def __init__(self, found: Callable[[str, int, str], None]) -> None:
        self._found = found
        self._zeroconf = None
        self._browser = None
        self._lock = threading.Lock()

    def start(self) -> None:
        from zeroconf import IPVersion, ServiceBrowser, ServiceStateChange, Zeroconf

        def resolve(zeroconf, service_type, name):
            try:
                info = zeroconf.get_service_info(service_type, name, timeout=3000)
            except Exception as error:  # noqa: BLE001 — zeroconf мог закрыться
                log.debug("Не удалось получить адрес %s: %s", name, error)
                return
            if info is None or not info.port:
                return
            addresses = info.parsed_addresses(IPVersion.V4Only) or info.parsed_addresses()
            if addresses:
                label = name.removesuffix("." + service_type)
                self._found(addresses[0], info.port, label)

        def handler(zeroconf, service_type, name, state_change):
            # Обработчик вызывается в потоке zeroconf — блокирующий запрос делаем в отдельном
            if state_change in (ServiceStateChange.Added, ServiceStateChange.Updated):
                threading.Thread(target=resolve, args=(zeroconf, service_type, name), daemon=True).start()

        with self._lock:
            self._zeroconf = Zeroconf(ip_version=IPVersion.All)
            self._browser = ServiceBrowser(self._zeroconf, protocol.SERVICE_TYPE, handlers=[handler])

    def stop(self) -> None:
        with self._lock:
            zeroconf, self._zeroconf, self._browser = self._zeroconf, None, None
        if zeroconf is not None:
            threading.Thread(target=zeroconf.close, daemon=True).start()


class NetworkClient(QObject):
    """Состояния: idle, searching, connecting, connected, failed."""

    message = Signal(object)          # protocol.Message
    state_changed = Signal(str, str)  # состояние, пояснение
    _discovered = Signal(str, int, str)

    def __init__(self, hello_provider: Callable[[], str]) -> None:
        super().__init__()
        self._hello = hello_provider
        self._socket: QWebSocket | None = None
        self._discovery: _Discovery | None = None
        self._address = ""
        self._running = False
        self._retry_delay = 2
        self._generation = 0
        self._retry_timer = QTimer(self, singleShot=True)
        self._retry_timer.timeout.connect(self._restart)
        self._warn_timer = QTimer(self, singleShot=True)
        self._warn_timer.timeout.connect(self._discovery_slow)
        self._discovered.connect(self._on_discovered)
        self.state = "idle"
        self.server_label = ""

    # MARK: - Управление

    def start(self, address: str) -> None:
        self._address = address.strip()
        self._running = True
        self._retry_delay = 2
        self._restart()

    def stop(self) -> None:
        self._running = False
        self._teardown()
        self._set_state("idle")

    def send(self, text: str) -> None:
        if self._socket is not None and self._socket.state() == QAbstractSocket.ConnectedState:
            self._socket.sendTextMessage(text)

    @property
    def connected(self) -> bool:
        return self.state == "connected"

    # MARK: - Внутреннее

    def _set_state(self, state: str, detail: str = "") -> None:
        self.state = state
        self.state_changed.emit(state, detail)

    def _teardown(self) -> None:
        self._generation += 1
        self._retry_timer.stop()
        self._warn_timer.stop()
        if self._discovery is not None:
            self._discovery.stop()
            self._discovery = None
        self._drop_socket()

    def _drop_socket(self) -> None:
        if self._socket is None:
            return
        socket, self._socket = self._socket, None
        for signal in (socket.connected, socket.disconnected, socket.textMessageReceived, socket.errorOccurred):
            try:
                signal.disconnect()
            except (RuntimeError, TypeError):
                pass
        socket.abort()
        socket.deleteLater()

    def _restart(self) -> None:
        self._teardown()
        if not self._running:
            return
        if self._address:
            host, port = parse_address(self._address)
            self.server_label = f"{host}:{port}"
            self._connect(host, port)
        else:
            self._browse()

    def _browse(self) -> None:
        self._set_state("searching", "Ищем офисный сервер в сети…")
        generation = self._generation
        self._discovery = _Discovery(lambda host, port, label: self._discovered.emit(host, port, f"{generation}|{label}"))
        try:
            self._discovery.start()
        except Exception as error:  # noqa: BLE001 — сеть может быть недоступна по разным причинам
            log.warning("mDNS недоступен: %s", error)
            self._set_state("failed", f"Поиск сервера не работает: {error}. Укажите адрес вручную.")
            self._schedule_retry()
            return
        self._warn_timer.start(DISCOVERY_WARN_SECONDS * 1000)

    def _discovery_slow(self) -> None:
        if self.state == "searching":
            self._set_state("failed", "Офисный сервер не найден. Попробуйте указать адрес вручную в настройках.")

    def _on_discovered(self, host: str, port: int, tagged: str) -> None:
        generation, _, label = tagged.partition("|")
        if int(generation) != self._generation or self._socket is not None or not self._running:
            return
        self._warn_timer.stop()
        if self._discovery is not None:
            self._discovery.stop()
            self._discovery = None
        self.server_label = f"{label} ({host}:{port})"
        log.info("Найден сервер %s", self.server_label)
        self._connect(host, port)

    def _connect(self, host: str, port: int) -> None:
        self._set_state("connecting", f"Подключаемся к {host}:{port}…")
        socket = QWebSocket()
        self._socket = socket
        generation = self._generation
        socket.connected.connect(lambda: self._on_connected(generation))
        socket.disconnected.connect(lambda: self._on_disconnected(generation))
        socket.textMessageReceived.connect(self._on_text)
        socket.errorOccurred.connect(lambda error: self._on_error(generation, error))
        socket.open(ws_url(host, port))

    def _on_connected(self, generation: int) -> None:
        if generation != self._generation or self._socket is None:
            return
        self._retry_delay = 2
        self._set_state("connected", self.server_label)
        self.send(self._hello())

    def _on_text(self, text: str) -> None:
        message = protocol.decode(text)
        if message is not None:
            self.message.emit(message)
        else:
            log.debug("Непонятное сообщение: %s", text[:200])

    def _on_error(self, generation: int, error) -> None:
        if generation != self._generation or self._socket is None:
            return
        detail = self._socket.errorString()
        log.info("Ошибка соединения: %s", detail)
        self._set_state("failed", f"Сервер не отвечает: {detail}")
        self._schedule_retry()

    def _on_disconnected(self, generation: int) -> None:
        if generation != self._generation or self._socket is None:
            return
        code = self._socket.closeCode()
        if self.state == "connected" or code != QWebSocketProtocol.CloseCodeNormal:
            self._set_state("failed", "Соединение с сервером потеряно")
        self._schedule_retry()

    def _schedule_retry(self) -> None:
        if not self._running or self._retry_timer.isActive():
            return
        delay = self._retry_delay
        self._retry_delay = min(self._retry_delay * 2, 30)
        self._drop_socket()
        self._retry_timer.start(delay * 1000)

    def retry_now(self) -> None:
        if self._running:
            self._retry_delay = 2
            self._restart()
