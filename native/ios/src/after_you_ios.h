#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

/// The iOS counterpart of the AfterYouAndroid singleton: the same method names, arguments
/// and signals for the services iOS has (secure storage, recovery copy, share sheet, invite
/// links, purchases, notifications and Game Center), so the GDScript wrappers stay shared.
class AfterYouIOS : public godot::Object {
	GDCLASS(AfterYouIOS, godot::Object)

protected:
	static void _bind_methods();

public:
	AfterYouIOS();
	~AfterYouIOS();

	void secure_put(const godot::String &p_name, const godot::String &p_value, const godot::String &p_request_id);
	void secure_get(const godot::String &p_name, const godot::String &p_request_id);
	void secure_remove(const godot::String &p_name, const godot::String &p_request_id);
	void secure_copy_recovery(const godot::String &p_player_id, const godot::String &p_recovery_code, const godot::String &p_request_id);

	void share_text(const godot::String &p_text);
	godot::String invite_link_take();

	void configure(const godot::String &p_public_key, const godot::String &p_player_id, const godot::String &p_mode, const godot::String &p_request_id);
	void get_offerings(const godot::String &p_request_id);
	void get_customer_info(const godot::String &p_request_id);
	void purchase_package(const godot::String &p_offering_id, const godot::String &p_package_id, const godot::String &p_request_id);
	void restore_purchases(const godot::String &p_request_id);

	void notification_set_categories(bool p_turns, bool p_hosting, bool p_requests, const godot::String &p_request_id);
	void notification_status(const godot::String &p_request_id);
	void notification_request_permission(const godot::String &p_request_id);
	void notification_get_token(const godot::String &p_request_id);
	void notification_set_binding(const godot::String &p_epoch, const godot::String &p_token, int64_t p_generation, const godot::String &p_request_id);
	void notification_clear_binding(const godot::String &p_request_id);
	void notification_pending_route(const godot::String &p_request_id);
	void notification_ack_route(const godot::String &p_event_id, const godot::String &p_request_id);
	void notification_disable(const godot::String &p_request_id);

	bool games_available();
	void games_status(const godot::String &p_request_id);
	void games_sign_in(const godot::String &p_request_id);
	void games_credential(const godot::String &p_web_client_id, const godot::String &p_request_id);
	void games_snapshot_open(const godot::String &p_name, const godot::String &p_request_id);
	void games_snapshot_commit(const godot::String &p_handle, const godot::String &p_data, const godot::String &p_description, const godot::String &p_request_id);
	void games_snapshot_resolve(const godot::String &p_handle, const godot::String &p_data, const godot::String &p_request_id);
	void games_snapshot_discard(const godot::String &p_handle, const godot::String &p_request_id);
};
