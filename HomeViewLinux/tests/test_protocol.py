"""Формат сообщений должен совпадать с синтезированным Swift Codable (Protocol.swift)."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from homeview import protocol  # noqa: E402
from homeview.net import parse_address  # noqa: E402
from homeview.office import translate_server_text  # noqa: E402
from mock_server import check_format  # noqa: E402


def parsed(text: str) -> tuple[str, dict]:
    obj = json.loads(text)
    assert len(obj) == 1
    return next(iter(obj.items()))


class EncodeTests(unittest.TestCase):
    def test_hello_shape(self):
        avatar = protocol.AvatarStyle("cap", 0x112233, 0x445566, 0xE0AC69)
        case, payload = parsed(protocol.hello("ID-1", "Алишер", "Backend", avatar, "active", ""))
        self.assertEqual(case, "hello")
        self.assertEqual(set(payload), {"id", "name", "team", "avatar", "status", "code", "version"})
        self.assertEqual(payload["avatar"], {"hat": "cap", "hatColor": 0x112233, "vestColor": 0x445566,
                                             "skinColor": 0xE0AC69})
        self.assertEqual(payload["version"], 4)
        self.assertEqual(check_format(case, payload), [])

    def test_unnamed_status(self):
        self.assertEqual(json.loads(protocol.status("busy")), {"status": {"_0": "busy"}})

    def test_chat_nil_recipient_omits_key(self):
        self.assertEqual(json.loads(protocol.chat(None, "всем")), {"chat": {"text": "всем"}})
        self.assertEqual(json.loads(protocol.chat("X", "hi")), {"chat": {"text": "hi", "to": "X"}})

    def test_chat_is_truncated(self):
        _, payload = parsed(protocol.chat("X", "я" * 500))
        self.assertEqual(len(payload["text"]), protocol.MAX_CHAT_LENGTH)

    def test_all_client_messages_pass_mock_validation(self):
        avatar = protocol.STANDARD_AVATAR
        for text in (protocol.hello("A", "B", "", avatar, "away", "code"), protocol.status("hidden"),
                     protocol.profile("N", "T", avatar), protocol.ping("A", "wave"), protocol.ping("A", "tea"),
                     protocol.projectile("A"), protocol.chat(None, "x"), protocol.chat("A", "x"),
                     protocol.respond("R", False), protocol.leave("R")):
            case, payload = parsed(text)
            self.assertEqual(check_format(case, payload), [], text)


class DecodeTests(unittest.TestCase):
    def test_peer_joined_unnamed(self):
        peer = {"id": "P", "name": "Жасур", "team": "iOS", "status": "away",
                "avatar": {"hat": "doppi", "hatColor": 1, "vestColor": 2, "skinColor": 3}}
        message = protocol.decode(json.dumps({"peerJoined": {"_0": peer}}))
        self.assertEqual(message.case, "peerJoined")
        info = protocol.PeerInfo.from_json(message.value)
        self.assertEqual((info.name, info.status, info.avatar.hat), ("Жасур", "away", "doppi"))

    def test_welcome_named(self):
        message = protocol.decode('{"welcome":{"you":"X","peers":[],"rooms":[]}}')
        self.assertEqual(message.case, "welcome")
        self.assertIsNone(message.value)
        self.assertEqual(message.data["peers"], [])

    def test_room_optional_fields_missing(self):
        message = protocol.decode('{"room":{"_0":{"id":"R","game":"tennis","hostID":"H","players":["H"],'
                                  '"phase":"lobby"}}}')
        room = protocol.RoomInfo.from_json(message.value)
        self.assertIsNone(room.starts_at)
        self.assertIsNone(room.teams)

    def test_garbage(self):
        for text in ("", "[]", '{"a":1}', '{"a":{},"b":{}}', "not json"):
            self.assertIsNone(protocol.decode(text), text)

    def test_unknown_values_fall_back(self):
        info = protocol.PeerInfo.from_json({"id": "1", "status": "dancing", "avatar": {"hat": "crown"}})
        self.assertEqual((info.status, info.avatar.hat), ("active", "doppi"))


class MiscTests(unittest.TestCase):
    def test_parse_address(self):
        self.assertEqual(parse_address("192.168.1.20"), ("192.168.1.20", 47777))
        self.assertEqual(parse_address("build-mini.local:5000"), ("build-mini.local", 5000))
        self.assertEqual(parse_address("ws://host:1/"), ("host", 1))
        self.assertEqual(parse_address("[fe80::1]:9"), ("fe80::1", 9))

    def test_translate(self):
        self.assertEqual(translate_server_text("Ofis kodi noto‘g‘ri"), "Неверный код офиса")
        self.assertIn("занят", translate_server_text("Жасур hozir band — xabar keyinroq"))
        self.assertEqual(translate_server_text("что-то новое"), "что-то новое")


if __name__ == "__main__":
    unittest.main()
