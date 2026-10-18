// amxx-testenv: hamsandwich on the port. RegisterHam reads the C++ vtable of a temporary
// "player" entity's private data and patches the Ham_Spawn slot; the port's entities have no
// vtable. Logs to addons/amxmodx/logs/ham_test.log.
#include <amxmodx>
#include <hamsandwich>

new const LOG[] = "ham_test.log";

public plugin_init()
{
	register_plugin("ham_test", "0.1", "amxx-testenv");
	log_to_file(LOG, "plugin_init: IsHamValid(Ham_Spawn)=%d; calling RegisterHam(Ham_Spawn, ^"player^")", IsHamValid(Ham_Spawn));
	new HamHook:h = RegisterHam(Ham_Spawn, "player", "fw_spawn_post", 1);
	log_to_file(LOG, "RegisterHam returned %d", h);
}

public fw_spawn_post(id)
{
	log_to_file(LOG, "Ham_Spawn post: id=%d alive=%d", id, is_user_alive(id));
}
