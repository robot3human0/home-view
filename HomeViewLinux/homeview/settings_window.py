"""Окно настроек: офис, человечек (с живым предпросмотром), экран."""

from __future__ import annotations

from typing import Callable

from PySide6.QtCore import QPointF, Qt, QTimer
from PySide6.QtGui import QColor, QIcon, QLinearGradient, QPainter, QPixmap
from PySide6.QtGui import QStandardItemModel
from PySide6.QtWidgets import (QCheckBox, QColorDialog, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
                               QGroupBox, QHBoxLayout, QLabel, QLineEdit, QMenu, QMessageBox, QSlider,
                               QToolButton, QVBoxLayout, QWidget)

from . import art, gpu, season as seasons
from .avatar import PeerAvatar
from .protocol import AvatarStyle, PeerInfo
from .profiling import measure
from .settings import Settings

HAT_TITLES = {"doppi": "Тюбетейка", "cap": "Кепка", "beanie": "Шапка", "strawHat": "Соломенная шляпа"}
HAT_COLORS = [0x1E3A5F, 0x7B1E1E, 0x2E4D2E, 0x4A2C6B, 0xC62828, 0x1565C0, 0xF9A825, 0x37474F]
VEST_COLORS = [0x1E88E5, 0xE53935, 0x43A047, 0xFB8C00, 0x8E24AA, 0x546E7A, 0x00897B, 0x6D4C41]
SKIN_COLORS = [0xFFDBAC, 0xF1C27D, 0xE0AC69, 0xC68642, 0x8D5524, 0x5C3A21]
SKY = {
    "winter": ((0.06, 0.12, 0.23), (0.20, 0.33, 0.53)),
    "spring": ((0.45, 0.70, 0.92), (0.78, 0.90, 0.98)),
    "summer": ((0.22, 0.60, 0.92), (0.70, 0.88, 0.99)),
    "autumn": ((0.36, 0.30, 0.42), (0.85, 0.60, 0.42)),
}


def _swatch(hex_value: int, size: int = 18) -> QIcon:
    pixmap = QPixmap(size, size)
    pixmap.fill(art.qcolor(hex_value))
    return QIcon(pixmap)


class ColorButton(QToolButton):
    def __init__(self, presets: list[int], value: int, on_change: Callable[[], None]) -> None:
        super().__init__()
        self.value = value
        self._on_change = on_change
        self.setPopupMode(QToolButton.InstantPopup)
        self.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        menu = QMenu(self)
        for hex_value in presets:
            menu.addAction(_swatch(hex_value), f"#{hex_value:06X}", lambda h=hex_value: self.set_value(h))
        menu.addSeparator()
        menu.addAction("Другой цвет…", self._custom)
        self.setMenu(menu)
        self._refresh()

    def _custom(self) -> None:
        color = QColorDialog.getColor(art.qcolor(self.value), self, "Выберите цвет")
        if color.isValid():
            self.set_value((color.red() << 16) | (color.green() << 8) | color.blue())

    def set_value(self, value: int) -> None:
        self.value = value
        self._refresh()
        self._on_change()

    def _refresh(self) -> None:
        self.setIcon(_swatch(self.value))
        self.setText(f"#{self.value:06X}")


class AvatarPreview(QWidget):
    """Человечек шагает на месте на фоне неба текущего сезона."""

    def __init__(self) -> None:
        super().__init__()
        self.setFixedSize(230, 330)
        self.season = "winter"
        self.avatar: PeerAvatar | None = None
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._tick)
        self._timer.start(33)

    def set_info(self, info: PeerInfo, season_kind: str) -> None:
        self.season = season_kind
        if self.avatar is None:
            self.avatar = PeerAvatar(info, self.width() / 2, 4.2, self.devicePixelRatioF(), text_scale=1.3)
            self.avatar.pause = 1e9
        else:
            self.avatar.update_info(info)
        self.avatar.ground_y = self.height() - 22
        self.avatar.walking = info.status != "away"
        self.update()

    def _tick(self) -> None:
        if self.avatar and self.avatar.walking:
            self.avatar.walk_time += 0.033
            self.update()

    @measure("настройки: предпросмотр человечка")
    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        top, bottom = SKY.get(self.season, SKY["winter"])
        gradient = QLinearGradient(QPointF(0, 0), QPointF(0, self.height()))
        gradient.setColorAt(0, QColor.fromRgbF(*top))
        gradient.setColorAt(1, QColor.fromRgbF(*bottom))
        painter.setBrush(gradient)
        painter.setPen(Qt.NoPen)
        painter.drawRoundedRect(self.rect(), 12, 12)
        painter.setBrush(QColor(255, 255, 255, 60))
        painter.drawRoundedRect(0, self.height() - 22, self.width(), 22, 12, 12)
        if self.avatar:
            self.avatar.paint(painter)


class SettingsWindow(QDialog):
    def __init__(self, settings: Settings, status_text: Callable[[], str], choice: gpu.Choice,
                 restart: Callable[[], None], preview: Callable[..., None],
                 toast_sample: Callable[[float | None], None]) -> None:
        super().__init__(None)
        self.settings = settings
        self._status_text = status_text
        self._choice = choice
        self._restart = restart
        self._preview = preview
        self._toast_sample = toast_sample
        self._loading = False
        self._saved = False
        # Живой предпросмотр: изменения экрана применяются сразу, но не чаще раза в 80 мс
        self._preview_timer = QTimer(self, singleShot=True, interval=80)
        self._preview_timer.timeout.connect(self._apply_preview)
        self.setWindowTitle("HomeView — настройки")
        self.setMinimumWidth(620)

        # Офис
        self.office_enabled = QCheckBox("Подключаться к офису")
        self.name_edit = QLineEdit()
        self.name_edit.setMaxLength(32)
        self.team_edit = QLineEdit()
        self.team_edit.setMaxLength(24)
        self.team_edit.setPlaceholderText("например, Backend")
        self.code_edit = QLineEdit()
        self.code_edit.setPlaceholderText("если сервер его требует")
        self.address_edit = QLineEdit()
        self.address_edit.setPlaceholderText("автоматически (mDNS), или 192.168.1.20")
        self.connection_label = QLabel()
        self.connection_label.setWordWrap(True)
        self.connection_label.setStyleSheet("color: palette(mid);")

        office = QGroupBox("Офис")
        office_form = QFormLayout(office)
        office_form.addRow(self.office_enabled)
        office_form.addRow("Имя:", self.name_edit)
        office_form.addRow("Команда:", self.team_edit)
        office_form.addRow("Код офиса:", self.code_edit)
        office_form.addRow("Адрес сервера:", self.address_edit)
        office_form.addRow(self.connection_label)

        # Человечек
        style = settings.avatar
        self.hat_combo = QComboBox()
        for key, title in HAT_TITLES.items():
            self.hat_combo.addItem(title, key)
        self.hat_combo.setCurrentIndex(max(0, self.hat_combo.findData(style.hat)))
        self.hat_color = ColorButton(HAT_COLORS, style.hat_color, self._refresh_preview)
        self.vest_color = ColorButton(VEST_COLORS, style.vest_color, self._refresh_preview)
        self.skin_color = ColorButton(SKIN_COLORS, style.skin_color, self._refresh_preview)
        self.preview = AvatarPreview()

        figure = QGroupBox("Человечек")
        figure_row = QHBoxLayout(figure)
        figure_row.addWidget(self.preview)
        figure_form = QFormLayout()
        figure_form.addRow("Головной убор:", self.hat_combo)
        self.hat_color_label = QLabel()
        figure_form.addRow(self.hat_color_label, self.hat_color)
        figure_form.addRow("Куртка:", self.vest_color)
        figure_form.addRow("Кожа:", self.skin_color)
        self.hat_hint = QLabel()
        self.hat_hint.setWordWrap(True)
        self.hat_hint.setStyleSheet("font-style: italic;")
        figure_form.addRow(self.hat_hint)
        figure_row.addLayout(figure_form, 1)

        # Экран
        self.effects_check = QCheckBox("Показывать сезонные осадки")
        self.season_combo = QComboBox()
        self.season_combo.addItem(f"Автоматически ({seasons.resolve('auto').title.lower()})", "auto")
        for kind in seasons.ORDER:
            item = seasons.SEASONS[kind]
            self.season_combo.addItem(f"{item.emoji} {item.title}", kind)
        self.density_slider = self._slider(10, 200)
        self.scale_slider = self._slider(60, 400)
        self.text_slider = self._slider(100, 400)
        self.toast_slider = self._slider(100, 300)
        self.toast_value = QLabel()
        self.toast_slider.valueChanged.connect(lambda v: self.toast_value.setText(f"{v / 100:.1f}×"))
        self.scale_value = QLabel()
        self.text_value = QLabel()
        self.scale_slider.valueChanged.connect(lambda v: self.scale_value.setText(f"{v / 100:.1f}×"))
        self.text_slider.valueChanged.connect(lambda v: self.text_value.setText(f"{v / 100:.1f}×"))
        self.fps_combo = QComboBox()
        for fps in (20, 30, 60):
            self.fps_combo.addItem(f"{fps} кадров/с", fps)
        self.renderer_combo = self._renderer_combo()
        self.renderer_label = QLabel(self._renderer_text())
        self.renderer_label.setWordWrap(True)
        self.renderer_label.setStyleSheet("color: palette(mid); font-size: 11px;")
        self.auto_away_check = QCheckBox("Статус «Отошёл», если 5 минут не трогать компьютер")
        self.autostart_check = QCheckBox("Запускать при входе в систему")

        screen = QGroupBox("Экран")
        screen_form = QFormLayout(screen)
        screen_form.addRow(self.effects_check)
        screen_form.addRow("Сезон:", self.season_combo)
        screen_form.addRow("Плотность осадков:", self.density_slider)
        screen_form.addRow("Размер человечков:", self._with_value(self.scale_slider, self.scale_value))
        screen_form.addRow("Размер надписей:", self._with_value(self.text_slider, self.text_value))
        screen_form.addRow("Размер уведомлений:", self._with_value(self.toast_slider, self.toast_value))
        screen_form.addRow("Плавность:", self.fps_combo)
        screen_form.addRow("Чем рисовать:", self.renderer_combo)
        screen_form.addRow(self.renderer_label)
        screen_form.addRow(self.auto_away_check)
        screen_form.addRow(self.autostart_check)

        buttons = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Save).setText("Сохранить")
        buttons.button(QDialogButtonBox.Cancel).setText("Отмена")
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)

        layout = QVBoxLayout(self)
        layout.addWidget(office)
        layout.addWidget(figure)
        layout.addWidget(screen)
        layout.addWidget(buttons)

        for signal in (self.name_edit.textChanged, self.team_edit.textChanged):
            signal.connect(self._refresh_preview)
        self.hat_combo.currentIndexChanged.connect(self._refresh_preview)
        self.hat_combo.currentIndexChanged.connect(self._update_hat_color_row)
        self._update_hat_color_row()
        self.season_combo.currentIndexChanged.connect(self._refresh_preview)
        self.office_enabled.toggled.connect(self._update_enabled)
        for slider in (self.density_slider, self.scale_slider, self.text_slider, self.toast_slider):
            slider.valueChanged.connect(self._schedule_preview)
        # Пример карточки — пока двигают ползунок размера уведомлений
        self._toast_sample_timer = QTimer(self, singleShot=True, interval=250)
        self._toast_sample_timer.timeout.connect(self._show_toast_sample)
        self.toast_slider.valueChanged.connect(lambda _: None if self._loading else self._toast_sample_timer.start())
        for combo in (self.season_combo, self.fps_combo):
            combo.currentIndexChanged.connect(self._schedule_preview)
        self.effects_check.toggled.connect(self._schedule_preview)

        self._status_timer = QTimer(self)
        self._status_timer.timeout.connect(self._update_status)
        self._status_timer.start(1000)
        self.load()

    @staticmethod
    def _with_value(slider: QSlider, label: QLabel) -> QWidget:
        box = QWidget()
        row = QHBoxLayout(box)
        row.setContentsMargins(0, 0, 0, 0)
        row.addWidget(slider, 1)
        label.setMinimumWidth(36)
        row.addWidget(label)
        return box

    @staticmethod
    def _slider(lo: int, hi: int) -> QSlider:
        slider = QSlider(Qt.Horizontal)
        slider.setRange(lo, hi)
        slider.setSingleStep(10)
        slider.setPageStep(20)
        return slider

    def _schedule_preview(self, *_) -> None:
        if not self._loading:
            self._preview_timer.start()

    def _apply_preview(self) -> None:
        self._preview(self.season_combo.currentData() or "auto", self.density_slider.value() / 100,
                      self.scale_slider.value() / 100, self.text_slider.value() / 100,
                      self.effects_check.isChecked(), self.fps_combo.currentData() or 30,
                      self.toast_slider.value() / 100)

    def _show_toast_sample(self) -> None:
        self._apply_preview()  # сначала масштаб, потом пример
        self._toast_sample(self.toast_slider.value() / 100)

    def _revert_preview(self) -> None:
        """Отмена: экран возвращается к сохранённым настройкам."""
        self._preview_timer.stop()
        s = self.settings
        self._preview(s.season, s.density, s.avatar_scale, s.text_scale, s.effects_enabled, s.fps, s.toast_scale)
        self._toast_sample(None)

    def reject(self) -> None:
        if not self._saved:
            self._revert_preview()
        super().reject()

    def load(self) -> None:
        self._loading = True
        self._saved = False
        s = self.settings
        self.office_enabled.setChecked(s.office_enabled)
        self.name_edit.setText(s.display_name)
        self.team_edit.setText(s.team)
        self.code_edit.setText(s.office_code)
        self.address_edit.setText(s.server_address)
        self.effects_check.setChecked(s.effects_enabled)
        self.season_combo.setCurrentIndex(max(0, self.season_combo.findData(s.season)))
        self.density_slider.setValue(round(s.density * 100))
        self.scale_slider.setValue(round(s.avatar_scale * 100))
        self.text_slider.setValue(round(s.text_scale * 100))
        self.toast_slider.setValue(round(s.toast_scale * 100))
        self.toast_value.setText(f"{s.toast_scale:.1f}×")
        self.scale_value.setText(f"{s.avatar_scale:.1f}×")
        self.text_value.setText(f"{s.text_scale:.1f}×")
        self.fps_combo.setCurrentIndex(max(0, self.fps_combo.findData(s.fps)))
        self.renderer_combo.setCurrentIndex(max(0, self.renderer_combo.findData(s.renderer)))
        self.auto_away_check.setChecked(s.auto_away)
        self.autostart_check.setChecked(s.autostart)
        self._update_enabled()
        self._update_status()
        self._refresh_preview()
        self._loading = False

    def _style(self) -> AvatarStyle:
        return AvatarStyle(hat=self.hat_combo.currentData(), hat_color=self.hat_color.value,
                           vest_color=self.vest_color.value, skin_color=self.skin_color.value)

    def _update_hat_color_row(self, *_) -> None:
        """Цвет перекрашивает не все уборы (так нарисованы спрайты Mac-версии) — подписываем, что именно."""
        hat = self.hat_combo.currentData()
        label, hint, enabled = {
            "beanie": ("Цвет шапки:", "Перекрашивается вся шапка, помпон остаётся белым.", True),
            "cap": ("Цвет кепки:", "Перекрашивается вся кепка.", True),
            "strawHat": ("Цвет ленты:", "У соломенной шляпы перекрашивается только лента на тулье.", True),
            "doppi": ("Цвет убора:", "У тюбетейки свой узор — цвет не меняется.", False),
        }.get(hat, ("Цвет убора:", "", True))
        self.hat_color_label.setText(label)
        self.hat_hint.setText(hint)
        self.hat_color.setEnabled(enabled)

    def _refresh_preview(self) -> None:
        name = self.name_edit.text().strip() or "Без имени"
        info = PeerInfo(id="preview", name=name, team=self.team_edit.text().strip(),
                        avatar=self._style(), status="active")
        self.preview.set_info(info, seasons.resolve(self.season_combo.currentData() or "auto").kind)

    def _update_enabled(self) -> None:
        on = self.office_enabled.isChecked()
        for widget in (self.code_edit, self.address_edit):
            widget.setEnabled(on)

    def _update_status(self) -> None:
        self.connection_label.setText(self._status_text())

    def _renderer_combo(self) -> QComboBox:
        available = gpu.describe_available()
        combo = QComboBox()
        model: QStandardItemModel = combo.model()
        discrete, integrated = available["discrete"], available["integrated"]
        entries = [
            ("auto", "Автоматически (дискретная, если есть)", True, ""),
            ("discrete", f"Дискретная — {discrete}" if discrete else "Дискретная — не найдена", bool(discrete),
             "" if discrete else "В системе нет дискретной видеокарты"),
            ("integrated", f"Встроенная — {integrated}" if integrated else "Встроенная — не найдена",
             bool(integrated),
             "" if integrated else "Встроенная графика не видна системе. На ноутбуках с MUX-переключателем "
                                   "её включают в BIOS / фирменной утилите (режим Hybrid / Optimus)."),
            ("cpu", "Процессор (без видеокарты) — медленно", True, ""),
        ]
        for key, title, enabled, tip in entries:
            combo.addItem(title, key)
            item = model.item(combo.count() - 1)
            item.setEnabled(enabled)
            if tip:
                item.setToolTip(tip)
        return combo

    def _renderer_text(self) -> str:
        c = self._choice
        if c.used == "cpu":
            text = "Сейчас: процессор ⚠ — повышенная нагрузка на CPU"
        else:
            text = f"Сейчас: {c.renderer}"
        if c.notes:
            text += "\n" + "; ".join(c.notes)
        return text + "\nСмена применяется после перезапуска HomeView."

    def _save(self) -> None:
        if self.office_enabled.isChecked() and not self.name_edit.text().strip():
            self.name_edit.setFocus()
            self.name_edit.setPlaceholderText("Имя обязательно — его увидят коллеги")
            return
        renderer = self.renderer_combo.currentData()
        renderer_changed = renderer != self.settings.renderer
        if renderer_changed and renderer == "cpu":
            answer = QMessageBox.warning(
                self, "Рисовать процессором?",
                "Без видеокарты осадки и анимации рисует процессор — это заметная постоянная нагрузка "
                "(у нас на тестах — около половины ядра) и быстрее разряжается батарея.\n\n"
                "Включить всё равно?",
                QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel)
            if answer != QMessageBox.Yes:
                return
        self.settings.save(
            configured=True,
            office_enabled=self.office_enabled.isChecked(),
            display_name=self.name_edit.text(),
            team=self.team_edit.text(),
            office_code=self.code_edit.text(),
            server_address=self.address_edit.text(),
            avatar=self._style(),
            effects_enabled=self.effects_check.isChecked(),
            season=self.season_combo.currentData(),
            density=self.density_slider.value() / 100,
            avatar_scale=self.scale_slider.value() / 100,
            text_scale=self.text_slider.value() / 100,
            toast_scale=self.toast_slider.value() / 100,
            fps=self.fps_combo.currentData(),
            auto_away=self.auto_away_check.isChecked(),
            autostart=self.autostart_check.isChecked(),
            renderer=renderer,
        )
        self._saved = True
        self._preview_timer.stop()
        self.accept()
        if renderer_changed:
            answer = QMessageBox.question(None, "Перезапустить HomeView?",
                                          "Видеокарта меняется только при запуске. Перезапустить сейчас?",
                                          QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes)
            if answer == QMessageBox.Yes:
                self._restart()
