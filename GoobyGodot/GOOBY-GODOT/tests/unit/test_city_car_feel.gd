extends TestCase
## W3a — CityCarFeel: Fahrgefühl-Zahlen 1:1 aus carFeel.js/DRIVE_TUNING
## (§C7.2 verbatim) + die frameratenunabhängige Mathematik.

const DEG := PI / 180.0


func test_konstanten_verbatim() -> void:
	assert_almost(CityCarFeel.STEER_SMOOTH_TAU_S, 0.12, 1e-9, "τ = 120 ms")
	assert_almost(CityCarFeel.STEER_RATE_CAP_RAD_S, 90.0 * DEG, 1e-9, "Yaw-Cap 90°/s")
	assert_almost(CityCarFeel.ASSIST_MAX_RATE_RAD_S, 8.0 * DEG, 1e-9)
	assert_almost(CityCarFeel.ASSIST_FADE_END_RAD, 25.0 * DEG, 1e-9)
	assert_almost(CityCarFeel.ASSIST_OFF_DEFLECTION, 0.4, 1e-9)
	assert_almost(CityCarFeel.CAM_POS_LERP_K, 4.0, 1e-9, "Chase-Cam k = 4/s")
	assert_almost(CityCarFeel.CAM_LOOKAHEAD_M, 6.0, 1e-9)
	assert_almost(CityCarFeel.BASE_SPEED, 9.0, 1e-9)
	assert_almost(CityCarFeel.MAX_SPEED, 13.0, 1e-9)
	assert_almost(CityCarFeel.SPEED_RAMP_SEC, 22.0, 1e-9)
	assert_almost(CityCarFeel.STEER_RATE, 1.9, 1e-9)
	assert_almost(CityCarFeel.BRAKE_DECEL, 12.0, 1e-9)
	assert_almost(CityCarFeel.BRAKE_MIN_SPEED, 1.2, 1e-9)
	assert_almost(CityCarFeel.CAM_BACK, 10.5, 1e-9)
	assert_almost(CityCarFeel.CAM_HEIGHT, 5.6, 1e-9)
	assert_almost(CityCarFeel.LANE_OFFSET_M, 2.5, 1e-9)
	assert_almost(CityCarFeel.CAR_SCALE, 1.8, 1e-9)


func test_smooth_steer_erreicht_63_prozent_nach_tau() -> void:
	# Sprungantwort: nach exakt τ Sekunden 63,2 % — egal in wie vielen Frames.
	var ein_schritt := CityCarFeel.smooth_steer(0.0, 1.0, 0.12)
	assert_almost(ein_schritt, 1.0 - exp(-1.0), 1e-6)
	var viele := 0.0
	for _i in 120:
		viele = CityCarFeel.smooth_steer(viele, 1.0, 0.001)
	assert_almost(viele, ein_schritt, 1e-3, "frameratenunabhängig")
	assert_almost(CityCarFeel.smooth_steer(0.5, 1.0, 0.0), 0.5, 1e-9, "dt=0 → unverändert")


func test_steer_yaw_rate_cap() -> void:
	assert_almost(
		CityCarFeel.steer_yaw_rate(1.0, 1.9, 1.0), 90.0 * DEG, 1e-9, "1.9 rad/s → gedeckelt"
	)
	assert_almost(CityCarFeel.steer_yaw_rate(-1.0, 1.9, 1.0), -90.0 * DEG, 1e-9)
	assert_almost(CityCarFeel.steer_yaw_rate(0.5, 1.9, 0.8), 0.5 * 1.9 * 0.8, 1e-9, "unter Cap roh")


func test_assist_kurve() -> void:
	assert_almost(CityCarFeel.assist_fade(0.0), 1.0, 1e-9)
	assert_almost(CityCarFeel.assist_fade(12.5 * DEG), 0.5, 1e-6, "linear bis 25°")
	assert_almost(CityCarFeel.assist_fade(30.0 * DEG), 0.0, 1e-9, "hart 0 jenseits")
	assert_almost(CityCarFeel.assist_rate(10.0 * DEG, 0.39), 8.0 * DEG * (1.0 - 10.0 / 25.0), 1e-6)
	assert_almost(CityCarFeel.assist_rate(10.0 * DEG, 0.4), 0.0, 1e-9, "≥40 % Auslenkung = aus")
	assert_true(CityCarFeel.assist_rate(-10.0 * DEG, 0.0) < 0.0, "signiert Richtung Kardinale")


func test_cam_follow_und_fov() -> void:
	assert_almost(CityCarFeel.cam_follow_factor(1.0), 1.0 - exp(-4.0), 1e-9)
	assert_almost(CityCarFeel.cam_follow_factor(0.0), 0.0, 1e-9)
	assert_almost(CityCarFeel.chase_fov(9.0), 55.0, 1e-9)
	assert_almost(CityCarFeel.chase_fov(13.0), 60.0, 1e-9)
	assert_almost(CityCarFeel.chase_fov(11.0), 57.5, 1e-9, "linear dazwischen")
	assert_almost(CityCarFeel.chase_fov(15.0), 60.0, 1e-9, "über MAX geklemmt")


func test_target_speed_rampe() -> void:
	assert_almost(CityCarFeel.target_speed(0.0), 9.0, 1e-9, "Basis 9 m/s")
	assert_almost(CityCarFeel.target_speed(11.0), 11.0, 1e-9, "halbe Rampe")
	assert_almost(CityCarFeel.target_speed(22.0), 13.0, 1e-9, "voll nach 22 s")
	assert_almost(CityCarFeel.target_speed(60.0), 13.0, 1e-9, "geklemmt")


func test_step_speed() -> void:
	assert_almost(CityCarFeel.step_speed(9.0, 9.0, true, 0.5), 3.0, 1e-9, "Bremse 12 m/s²")
	assert_almost(CityCarFeel.step_speed(1.5, 9.0, true, 1.0), 1.2, 1e-9, "Kriech-Minimum")
	assert_almost(CityCarFeel.step_speed(0.0, 9.0, false, 1.0), 5.5, 1e-9, "rauf mit 5.5")
	assert_almost(CityCarFeel.step_speed(13.0, 9.0, false, 0.1), 13.0 - 0.9, 1e-9, "runter mit 9")
	assert_almost(CityCarFeel.step_speed(8.9, 9.0, false, 1.0), 9.0, 1e-9, "nie überschießen")


func test_wrap_angle_und_damp() -> void:
	assert_almost(CityCarFeel.wrap_angle(3.0 * PI), PI, 1e-9)
	assert_almost(CityCarFeel.wrap_angle(-PI), PI, 1e-9, "(-π, π] — -π wickelt auf π")
	assert_almost(CityCarFeel.speed_damp(0.0), 1.0, 1e-9)
	assert_almost(CityCarFeel.speed_damp(13.0), 0.75, 1e-9, "voll = 25 % gedämpft")
