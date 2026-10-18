// amxx-testenv: basic AMXX smoke test for the TS Rust port.
// Logs to addons/amxmodx/logs/amxx_test.log: plugin_init, client_putinserver, DeathMsg, and a
// probe every 10 s that uses fun (get/set_user_health) and engine (entity_get_vector/float) on
// every alive player (bots included). Server command: amxx_test_probe.
#include <amxmodx>
#include <fun>
#include <engine>

new const LOG[] = "amxx_test.log";
new bool:g_healed[33];

public plugin_init()
{
	register_plugin("amxx_test", "0.1", "amxx-testenv");
	new map[32], mod[32];
	get_mapname(map, charsmax(map));
	get_modname(mod, charsmax(mod));
	log_to_file(LOG, "plugin_init: map=%s mod=%s maxplayers=%d", map, mod, get_maxplayers());
	register_srvcmd("amxx_test_probe", "cmd_probe");
	register_event("DeathMsg", "ev_death", "a");
	set_task(10.0, "probe", 0, "", 0, "b");
}

public plugin_cfg()
{
	log_to_file(LOG, "plugin_cfg");
}

public client_putinserver(id)
{
	new name[32];
	get_user_name(id, name, charsmax(name));
	g_healed[id] = false;
	log_to_file(LOG, "client_putinserver: id=%d name=^"%s^" bot=%d", id, name, is_user_bot(id));
}

public client_disconnected(id)
{
	log_to_file(LOG, "client_disconnected: id=%d", id);
}

public ev_death()
{
	new killer = read_data(1), victim = read_data(2);
	new kn[32], vn[32];
	if (killer >= 1 && killer <= 32) get_user_name(killer, kn, charsmax(kn));
	if (victim >= 1 && victim <= 32) get_user_name(victim, vn, charsmax(vn));
	log_to_file(LOG, "DeathMsg: killer=%d ^"%s^" victim=%d ^"%s^"", killer, kn, victim, vn);
}

public cmd_probe()
{
	probe();
	return PLUGIN_HANDLED;
}

public probe()
{
	new players[32], n;
	get_players(players, n);
	log_to_file(LOG, "probe: %d players", n);
	for (new i = 0; i < n; i++)
	{
		new id = players[i];
		new name[32];
		get_user_name(id, name, charsmax(name));
		new Float:origin[3];
		entity_get_vector(id, EV_VEC_origin, origin);
		new hp = get_user_health(id);
		new frags = get_user_frags(id);
		log_to_file(LOG, "  id=%d ^"%s^" alive=%d hp=%d frags=%d origin=(%.1f %.1f %.1f) classname check=%d",
			id, name, is_user_alive(id), hp, frags, origin[0], origin[1], origin[2], is_valid_ent(id));
		if (is_user_alive(id) && !g_healed[id])
		{
			set_user_health(id, 123);
			log_to_file(LOG, "  set_user_health(%d, 123) -> get_user_health=%d EV_FL_health=%.1f",
				id, get_user_health(id), entity_get_float(id, EV_FL_health));
			g_healed[id] = true;
		}
	}
}
