# Minimal VL53L0X (I2C ToF distance sensor) support
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import logging, math
from . import bus

# Default 7-bit I2C address is 0x29.
VL53L0X_DEFAULT_ADDR = 0x29
VL53L0X_I2C_SPEED = 100000

# Minimal register set for single-shot measurements.
REG_SYSRANGE_START = 0x00
REG_SYSTEM_SEQUENCE_CONFIG = 0x01
REG_SYSTEM_INTERMEASUREMENT_PERIOD = 0x04
REG_SYSTEM_INTERRUPT_CONFIG_GPIO = 0x0A
REG_SYSTEM_INTERRUPT_CLEAR = 0x0B
REG_RESULT_INTERRUPT_STATUS = 0x13
REG_RESULT_RANGE_STATUS = 0x14
REG_IDENTIFICATION_MODEL_ID = 0xC0
REG_MSRC_CONFIG_CONTROL = 0x60
REG_GPIO_HV_MUX_ACTIVE_HIGH = 0x84
REG_VHV_CONFIG_PAD_SCL_SDA_EXTSUP_HV = 0x89

# Minimal power-on sequence commonly used to bring VL53L0X out of its
# factory/default state before single-shot ranging.
REG_POWER_SEQUENCE_1 = 0x80
REG_POWER_SEQUENCE_2 = 0xFF
REG_POWER_SEQUENCE_3 = 0x91
REG_POWER_SEQUENCE_4 = 0x00

EXPECTED_MODEL_ID = 0xEE

DEFAULT_REPORT_TIME = 0.20
DEFAULT_SAMPLE_TIMEOUT = 0.50


class VL53L0X:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.config_name = config.get_name()
        self.name = config.get_name().split()[-1]
        self.reactor = self.printer.get_reactor()
        self.i2c = bus.MCU_I2C_from_config(
            config, default_addr=VL53L0X_DEFAULT_ADDR,
            default_speed=VL53L0X_I2C_SPEED)

        self.report_time = config.getfloat(
            'report_time', DEFAULT_REPORT_TIME, minval=0.02)
        self.sample_timeout = config.getfloat(
            'sample_timeout', DEFAULT_SAMPLE_TIMEOUT, minval=0.01)
        self.temp_cal_on_connect = config.getboolean('temp_cal_on_connect', True)
        self.distance_offset_mm = config.getfloat('distance_offset_mm', 0.0)

        self.distance_mm = None
        self.raw_distance_mm = None
        self.range_status = None
        self.last_measurement_time = None

        self.printer.add_object("vl53l0x " + self.name, self)
        self.printer.register_event_handler("klippy:connect", self.handle_connect)

        gcode = self.printer.lookup_object("gcode")
        # Klipper's gcode parser splits non-traditional commands on digits,
        # so register the command under the token it will actually parse.
        gcode.register_mux_command("QUERY_VL53", "SENSOR", self.name,
                                   self.cmd_QUERY_VL53L0X,
                                   desc=self.cmd_QUERY_VL53L0X_help)
        gcode.register_mux_command("CALIBRATE_VL_OFFSET", "SENSOR", self.name,
                       self.cmd_CALIBRATE_VL53,
                       desc=self.cmd_CALIBRATE_VL53_help)
        gcode.register_mux_command("CALIBRATE_VL_TEMP", "SENSOR", self.name,
                   self.cmd_CALIBRATE_VL53_TEMP,
                   desc=self.cmd_CALIBRATE_VL53_TEMP_help)
        gcode.register_mux_command("CALIBRATE_VL_FIRST_USE", "SENSOR", self.name,
                   self.cmd_CALIBRATE_VL53_FIRST_USE,
                   desc=self.cmd_CALIBRATE_VL53_FIRST_USE_help)

    def handle_connect(self):
        self._init_sensor()
        if self.temp_cal_on_connect:
            self._perform_temperature_calibration()

    def _read_register(self, reg, read_len=1):
        params = self.i2c.i2c_read([reg], read_len)
        return bytearray(params['response'])

    def _write_register(self, reg, value):
        self.i2c.i2c_write([reg, value])

    def _init_sensor(self):
        model_id = self._read_register(REG_IDENTIFICATION_MODEL_ID, 1)[0]
        if model_id != EXPECTED_MODEL_ID:
            logging.warning("vl53l0x %s: unexpected model id 0x%02x",
                            self.name, model_id)
        else:
            logging.info("vl53l0x %s: detected model id 0x%02x",
                         self.name, model_id)

        # Match the minimum parts of the upstream init flow that matter for
        # single-shot ranging and interrupt polling.
        self._write_register(REG_VHV_CONFIG_PAD_SCL_SDA_EXTSUP_HV, 0x01)
        self._write_register(REG_SYSTEM_SEQUENCE_CONFIG, 0xFF)
        self._write_register(REG_MSRC_CONFIG_CONTROL,
                             self._read_register(REG_MSRC_CONFIG_CONTROL, 1)[0] | 0x12)
        self._write_register(REG_SYSTEM_INTERRUPT_CONFIG_GPIO, 0x04)
        self._write_register(REG_GPIO_HV_MUX_ACTIVE_HIGH,
                             self._read_register(REG_GPIO_HV_MUX_ACTIVE_HIGH, 1)[0] & ~0x10)

        # Clear stale interrupt status before first measurement.
        self._write_register(REG_SYSTEM_INTERRUPT_CLEAR, 0x01)

    def _perform_single_ref_calibration(self, vhv_init_byte):
        # Equivalent to VL53L0X_PerformSingleRefCalibration() in ST API.
        self._write_register(REG_SYSRANGE_START, 0x01 | (vhv_init_byte & 0xff))
        self._wait_measurement_ready()
        self._write_register(REG_SYSTEM_INTERRUPT_CLEAR, 0x01)
        self._write_register(REG_SYSRANGE_START, 0x00)

    def _perform_temperature_calibration(self):
        # Equivalent to VL53L0X_PerformRefCalibration() sequence.
        self._write_register(REG_SYSTEM_SEQUENCE_CONFIG, 0x01)
        self._perform_single_ref_calibration(0x40)
        self._write_register(REG_SYSTEM_SEQUENCE_CONFIG, 0x02)
        self._perform_single_ref_calibration(0x00)
        self._write_register(REG_SYSTEM_SEQUENCE_CONFIG, 0xE8)

    def _wait_start_cleared(self):
        deadline = self.reactor.monotonic() + self.sample_timeout
        while self.reactor.monotonic() < deadline:
            if (self._read_register(REG_SYSRANGE_START, 1)[0] & 0x01) == 0:
                return
            self.reactor.pause(self.reactor.monotonic() + 0.002)
        raise self.printer.command_error(
            "vl53l0x %s: timeout waiting for measurement start" % (self.name,))

    def _wait_measurement_ready(self):
        deadline = self.reactor.monotonic() + self.sample_timeout
        while self.reactor.monotonic() < deadline:
            intr = self._read_register(REG_RESULT_INTERRUPT_STATUS, 1)[0]
            if intr & 0x07:
                return
            self.reactor.pause(self.reactor.monotonic() + 0.002)
        raise self.printer.command_error(
            "vl53l0x %s: timeout waiting for measurement" % (self.name,))

    def _take_single_measurement(self):
        # Discard any pending interrupt from an earlier conversion before
        # starting a new single-shot reading.
        self._write_register(REG_SYSTEM_INTERRUPT_CLEAR, 0x01)

        # Start single-shot ranging.
        self._write_register(REG_SYSRANGE_START, 0x01)
        self._wait_start_cleared()
        self._wait_measurement_ready()

        # Read RESULT_RANGE_STATUS block. Distance is in bytes 10/11.
        result = self._read_register(REG_RESULT_RANGE_STATUS, 12)
        range_status = result[0] & 0x1f
        distance_mm = (result[10] << 8) | result[11]

        self._write_register(REG_SYSTEM_INTERRUPT_CLEAR, 0x01)
        return distance_mm, range_status

    def _apply_offset(self, raw_distance_mm):
        corrected = int(round(raw_distance_mm + self.distance_offset_mm))
        return max(0, corrected)

    def _median(self, values):
        values = sorted(values)
        middle = len(values) // 2
        if len(values) & 1:
            return values[middle]
        return (values[middle - 1] + values[middle]) / 2.

    def _select_result_value(self, values, result):
        result = result.lower()
        if result == "median":
            return self._median(values)
        if result == "average":
            return sum(values) / float(len(values))
        if result == "min":
            return min(values)
        if result == "max":
            return max(values)
        raise self.printer.command_error(
            "vl53l0x %s: unknown result method '%s'"
            % (self.name, result))

    def read_distance(self, samples=1, sample_delay=0.03, result="median"):
        samples = int(samples)
        if samples < 1:
            raise self.printer.command_error(
                "vl53l0x %s: samples must be at least 1" % (self.name,))
        raw_values = []
        corrected_values = []
        statuses = []
        for sample in range(samples):
            raw_mm, range_status = self._take_single_measurement()
            raw_values.append(raw_mm)
            corrected_values.append(self._apply_offset(raw_mm))
            statuses.append(range_status)
            if sample + 1 < samples and sample_delay > 0.:
                self.reactor.pause(self.reactor.monotonic() + sample_delay)

        distance_value = self._select_result_value(corrected_values, result)
        raw_value = self._select_result_value(raw_values, result)
        avg_distance = sum(corrected_values) / float(len(corrected_values))
        variance = sum([(v - avg_distance) ** 2
                        for v in corrected_values]) / float(len(corrected_values))
        sigma = math.sqrt(variance)

        distance_mm = int(round(distance_value))
        raw_distance_mm = int(round(raw_value))
        status = max(statuses)
        self.raw_distance_mm = raw_distance_mm
        self.distance_mm = distance_mm
        self.range_status = status
        self.last_measurement_time = self.reactor.monotonic()
        return {
            'distance_mm': distance_mm,
            'raw_mm': raw_distance_mm,
            'status': status,
            'sigma': sigma,
            'mean_mm': avg_distance,
            'min_mm': min(corrected_values),
            'max_mm': max(corrected_values),
            'samples': list(corrected_values),
            'raw_samples': list(raw_values),
            'statuses': list(statuses),
        }

    def _sample_vl53l0x(self, eventtime):
        try:
            distance_mm, range_status = self._take_single_measurement()
            self.distance_mm = distance_mm
            self.range_status = range_status
            self.last_measurement_time = self.reactor.monotonic()
        except Exception:
            logging.exception("vl53l0x %s: sample failed", self.name)
        return eventtime + self.report_time

    cmd_QUERY_VL53L0X_help = "Query VL53L0X single distance reading"
    def cmd_QUERY_VL53L0X(self, gcmd):
        try:
            raw_distance_mm, range_status = self._take_single_measurement()
            distance_mm = self._apply_offset(raw_distance_mm)
            self.raw_distance_mm = raw_distance_mm
            self.distance_mm = distance_mm
            self.range_status = range_status
            self.last_measurement_time = self.reactor.monotonic()
            gcmd.respond_info(
                "VL53L0X %s: distance=%dmm raw=%dmm offset=%.2fmm status=%d"
                % (self.name, distance_mm, raw_distance_mm,
                   self.distance_offset_mm, range_status))
        except Exception:
            start_reg = self._read_register(REG_SYSRANGE_START, 1)[0]
            intr_reg = self._read_register(REG_RESULT_INTERRUPT_STATUS, 1)[0]
            logging.exception(
                "vl53l0x %s: query failed start=0x%02x intr=0x%02x",
                self.name, start_reg, intr_reg)
            raise

    cmd_CALIBRATE_VL53_help = (
        "Calibrate VL53 offset using known ACTUAL_MM; optional SAMPLES and SAVE=1"
    )
    def cmd_CALIBRATE_VL53(self, gcmd):
        actual_mm = gcmd.get_float("ACTUAL_MM", minval=0.)
        samples = gcmd.get_int("SAMPLES", 5, minval=1, maxval=50)
        save_cfg = gcmd.get_int("SAVE", 0, minval=0, maxval=1)

        raw_values = []
        statuses = []
        for _ in range(samples):
            raw_mm, range_status = self._take_single_measurement()
            raw_values.append(raw_mm)
            statuses.append(range_status)
            self.reactor.pause(self.reactor.monotonic() + 0.03)

        avg_raw_mm = sum(raw_values) / float(len(raw_values))
        new_offset_mm = actual_mm - avg_raw_mm
        self.distance_offset_mm = new_offset_mm

        corrected_mm = self._apply_offset(raw_values[-1])
        self.raw_distance_mm = raw_values[-1]
        self.distance_mm = corrected_mm
        self.range_status = statuses[-1]
        self.last_measurement_time = self.reactor.monotonic()

        msg = (
            "VL53L0X %s calibration: actual=%.2fmm avg_raw=%.2fmm "
            "new_offset=%.2fmm corrected_now=%dmm\n"
            "Set 'distance_offset_mm: %.3f' in [%s]"
            % (self.name, actual_mm, avg_raw_mm, new_offset_mm,
               corrected_mm, new_offset_mm, self.config_name)
        )

        if save_cfg:
            configfile = self.printer.lookup_object('configfile')
            configfile.set(self.config_name, 'distance_offset_mm',
                           "%.3f" % (new_offset_mm,))
            msg += (
                "\nThe SAVE_CONFIG command will update the printer config file"
                " with the above value and restart the printer."
            )
        gcmd.respond_info(msg)

    cmd_CALIBRATE_VL53_TEMP_help = (
        "Run VL53 temperature reference calibration (VHV/Phase style)"
    )
    def cmd_CALIBRATE_VL53_TEMP(self, gcmd):
        self._perform_temperature_calibration()
        gcmd.respond_info(
            "VL53L0X %s: temperature reference calibration completed"
            % (self.name,))

    cmd_CALIBRATE_VL53_FIRST_USE_help = (
        "Run first-use calibration: temperature ref + offset (ACTUAL_MM required)"
    )
    def cmd_CALIBRATE_VL53_FIRST_USE(self, gcmd):
        # Practical subset of ST first-use flow for this lightweight driver:
        # 1) reference temperature calibration, 2) offset calibration.
        self._perform_temperature_calibration()
        self.cmd_CALIBRATE_VL53(gcmd)

    def get_status(self, eventtime):
        age = None
        if self.last_measurement_time is not None:
            age = max(0., eventtime - self.last_measurement_time)
        return {
            'distance_mm': self.distance_mm,
            'raw_distance_mm': self.raw_distance_mm,
            'distance_offset_mm': self.distance_offset_mm,
            'range_status': self.range_status,
            'sample_age': age,
        }


def load_config_prefix(config):
    return VL53L0X(config)
