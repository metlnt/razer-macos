"""Low-level Razer HID protocol (90-byte feature reports) for Razer Naga Trinity."""
import time
import hid

VID, PID = 0x1532, 0x0067
REPORT_LEN = 90

STATUS = {0x00: "new", 0x01: "busy", 0x02: "ok", 0x03: "fail", 0x04: "timeout", 0x05: "not_supported"}


class RazerError(Exception):
    pass


def build_report(cmd_class, cmd_id, data_size, args=b"", transaction_id=0x1F):
    r = bytearray(REPORT_LEN)
    r[1] = transaction_id
    r[5] = data_size
    r[6] = cmd_class
    r[7] = cmd_id
    r[8:8 + len(args)] = args
    crc = 0
    for b in r[2:88]:
        crc ^= b
    r[88] = crc
    return bytes(r)


class RazerDevice:
    def __init__(self, transaction_id=0x1F):
        self.tid = transaction_id
        path = next((d["path"] for d in hid.enumerate(VID, PID) if d["interface_number"] == 0), None)
        if path is None:
            raise RazerError("Razer Naga Trinity not found")
        self.dev = hid.device()
        self.dev.open_path(path)

    def close(self):
        self.dev.close()

    def request(self, cmd_class, cmd_id, data_size, args=b"", retries=10):
        """Send a command, return (status, args bytes of response)."""
        self.dev.send_feature_report(b"\x00" + build_report(cmd_class, cmd_id, data_size, args, self.tid))
        for _ in range(retries):
            time.sleep(0.004)
            resp = bytes(self.dev.get_feature_report(0, REPORT_LEN + 1))
            if resp and len(resp) == REPORT_LEN + 1:
                resp = resp[1:]
            if resp[0] == 0x01:  # busy
                continue
            if resp[6] != cmd_class or resp[7] != cmd_id:
                continue
            return resp[0], resp[5], resp[8:88]
        raise RazerError(f"no response for {cmd_class:02x}:{cmd_id:02x}")
