"""Карточки в правом верхнем углу (аналог Toasts.swift): приглашения, сообщения, ошибки."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from PySide6.QtCore import QObject, QPoint, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QGuiApplication, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QToolButton, QVBoxLayout, QWidget

WIDTH = 340
MARGIN = 14
GAP = 10
MAX_VISIBLE = 5


@dataclass
class ToastAction:
    title: str
    callback: Callable[[], None]
    primary: bool = False


@dataclass
class Toast:
    icon: str
    title: str
    message: str = ""
    actions: list[ToastAction] = field(default_factory=list)
    auto_dismiss: float | None = 6.0
    key: str | None = None  # карточка с тем же ключом заменяет предыдущую


class _Card(QWidget):
    def __init__(self, toast: Toast, on_close: Callable[["_Card"], None], scale: float = 1.0) -> None:
        super().__init__(None)
        self.toast = toast
        self._on_close = on_close
        self.scale = scale
        k = scale

        def px(value: float) -> int:
            return max(1, round(value * k))
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
                            | Qt.X11BypassWindowManagerHint | Qt.WindowDoesNotAcceptFocus)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_DeleteOnClose)
        self.setFixedWidth(px(WIDTH))
        self.setStyleSheet(f"""
            QLabel {{ color: #F4F7FB; background: transparent; }}
            QLabel#title {{ font-weight: 600; font-size: {px(13)}px; }}
            QLabel#message {{ color: #C9D3E0; font-size: {px(12)}px; }}
            QLabel#icon {{ font-size: {px(22)}px; }}
            QPushButton {{ color: #F4F7FB; background: rgba(255,255,255,0.12); border: 1px solid rgba(255,255,255,0.18);
                          border-radius: {px(8)}px; padding: {px(5)}px {px(12)}px; font-size: {px(12)}px; }}
            QPushButton:hover {{ background: rgba(255,255,255,0.2); }}
            QPushButton[primary="true"] {{ background: #2F7FE0; border-color: #4C93EA; }}
            QPushButton[primary="true"]:hover {{ background: #3C8AEB; }}
            QToolButton {{ color: #9FB0C6; background: transparent; border: none; font-size: {px(14)}px; }}
            QToolButton:hover {{ color: #FFFFFF; }}
        """)

        root = QHBoxLayout(self)
        root.setContentsMargins(px(14), px(12), px(10), px(12))
        root.setSpacing(px(10))
        icon = QLabel(toast.icon, objectName="icon")
        icon.setAlignment(Qt.AlignTop)
        root.addWidget(icon)

        column = QVBoxLayout()
        column.setSpacing(px(4))
        title = QLabel(toast.title, objectName="title")
        title.setWordWrap(True)
        column.addWidget(title)
        if toast.message:
            message = QLabel(toast.message, objectName="message")
            message.setWordWrap(True)
            column.addWidget(message)
        if toast.actions:
            row = QHBoxLayout()
            row.setSpacing(px(8))
            row.setContentsMargins(0, px(6), 0, 0)
            for action in toast.actions:
                button = QPushButton(action.title)
                button.setProperty("primary", action.primary)
                button.setCursor(Qt.PointingHandCursor)
                button.clicked.connect(lambda _=False, a=action: self._run(a))
                row.addWidget(button)
            row.addStretch(1)
            column.addLayout(row)
        root.addLayout(column, 1)

        close = QToolButton()
        close.setText("✕")
        close.setCursor(Qt.PointingHandCursor)
        close.clicked.connect(self.dismiss)
        root.addWidget(close, 0, Qt.AlignTop)

        if toast.auto_dismiss:
            QTimer.singleShot(int(toast.auto_dismiss * 1000), self, self.dismiss)
        self.adjustSize()

    def _run(self, action: ToastAction) -> None:
        self.dismiss()
        action.callback()

    def dismiss(self) -> None:
        if self.property("closed"):
            return
        self.setProperty("closed", True)
        self._on_close(self)
        self.close()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        path = QPainterPath()
        radius = 14 * self.scale
        path.addRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), radius, radius)
        painter.fillPath(path, QColor(18, 28, 44, 236))
        painter.setPen(QPen(QColor(255, 255, 255, 40), 1))
        painter.drawPath(path)


class ToastManager(QObject):
    def __init__(self, scale: float = 1.0) -> None:
        super().__init__()
        self._cards: list[_Card] = []
        self.scale = scale

    def post(self, toast: Toast) -> None:
        if toast.key:
            for card in list(self._cards):
                if card.toast.key == toast.key:
                    card.dismiss()
        card = _Card(toast, self._closed, self.scale)
        self._cards.insert(0, card)
        while len(self._cards) > MAX_VISIBLE:
            self._cards[-1].dismiss()
        self._layout()
        card.show()
        card.raise_()

    def dismiss_key(self, key: str) -> None:
        for card in list(self._cards):
            if card.toast.key == key:
                card.dismiss()

    def _closed(self, card: _Card) -> None:
        if card in self._cards:
            self._cards.remove(card)
            self._layout()

    def _layout(self) -> None:
        screen = QGuiApplication.primaryScreen()
        if screen is None:
            return
        area = screen.availableGeometry()
        y = area.top() + MARGIN
        for card in self._cards:
            card.adjustSize()
            card.move(QPoint(area.right() - card.width() - MARGIN, y))
            y += card.height() + GAP
