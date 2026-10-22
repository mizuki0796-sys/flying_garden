extends Resource
class_name MovementSettings

@export_category("Mass and propulsion")
@export var tile_size := 32.0
@export var initial_mass := 28.0
@export var base_thrust := 240.0
@export var drag_coefficient := 0.15
# 0.9 is calibrated to the design's 3.5-5.5 second stopping-time acceptance band.
@export var passive_brake_ratio := 0.9
@export var emergency_brake_multiplier := 10.0

@export_category("Energy")
@export var base_energy_capacity := 150.0
@export var moving_energy_per_second := 2.0
@export var thrust_energy_per_second := 3.0
@export var autopilot_energy_per_second := 4.0
@export var emergency_stop_cost := 25.0
@export var hook_launch_cost := 8.0
@export var hook_miss_cost := 5.0
@export var loaded_hook_energy_per_second := 4.0
@export var loaded_hook_mass_energy_per_second := 0.15
@export var rice_energy := 15.0
@export var energy_crop_energy := 35.0

@export_category("Camera and navigation")
@export var god_zoom_default := 0.55
@export var god_zoom_min := 0.4
@export var god_zoom_max := 1.0
@export var focus_zoom_default := 1.4
@export var focus_zoom_min := 1.0
@export var focus_zoom_max := 2.0
@export var camera_look_ahead_seconds := 0.3
@export var camera_smooth_time := 0.15
@export var view_transition_time := 0.4
@export var focus_pan_limit := 176.0
@export var edge_pan_speed := 150.0
@export var soft_boundary_tiles := 75.0
@export var soft_boundary_speed_ratio := 0.5

@export_category("Autopilot and warning")
@export var autopilot_cruise_ratio := 0.6
@export var autopilot_min_energy := 20.0
@export var warning_radius_tiles := 4.0
@export var autopilot_arrival_radius := 12.0

@export_category("Grapple")
@export var hook_range_tiles := 10.0
@export var hook_extend_speed := 525.0
@export var hook_empty_retract_speed := 640.0
@export var hook_loaded_retract_ratio := 0.5
@export var hook_dangle_time := 0.6
@export var hook_miss_retract_time := 0.5
