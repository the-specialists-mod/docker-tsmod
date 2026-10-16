/* 
	TSMessages Plus, by Shurik3n
	This plugin adds some nicer effect to those boring old
	green messages in the specialists, such as <Name> is a killer and so on
	
	Special thanks to Jordan44053
*/

#include <amxmodx>
#if AMXX_VERSION_NUM < 175
#include <engine>
#endif

#define PLUGIN "TSMessages Plus"
#define VERSION "1.0"
#define AUTHOR "Shurik3n"

#define RED 1
#define GREEN 2
#define BLUE 3

new g_constkills[33]
new g_lastkill

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR)
	register_message(get_user_msgid("TSMessage"),"hook_tsmessage")
	register_message(get_user_msgid("DeathMsg"),"hook_death")
	
	register_cvar("amx_tsmsgs","1")
	register_cvar("amx_randommsgs","0")
}

public client_connect(id) g_constkills[id] = 0

public client_disconnect(id) g_constkills[id] = 0

public hook_tsmessage(id) {
	if(get_cvar_num("amx_tsmsgs") != 1) return PLUGIN_CONTINUE
	if(get_cvar_num("amx_randommsgs") == 1) {
		set_msg_arg_int(BLUE,0,random_num(0,255))
		set_msg_arg_int(RED,0,random_num(0,255))
		set_msg_arg_int(GREEN,0,random_num(0,255))
		return PLUGIN_CONTINUE
	}
	static message[128]
	//Get the outgoing message's text
	get_msg_arg_string(6,message,127)
	
	if(containi(message,"Press Fire to play!") != -1) return PLUGIN_CONTINUE
	
	if(containi(message,"Kung-Fu style!") == strlen(message)-14) {
		set_msg_arg_int(BLUE,0,255)
		set_msg_arg_int(GREEN,0,255)
		return PLUGIN_CONTINUE
	}
	else if(equal(message,"DoubleFrag",10)) {
		set_msg_arg_int(GREEN,0,0)
		set_msg_arg_int(BLUE,0,255)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Sliding style!") == strlen(message)-14) {
		set_msg_arg_int(GREEN,0,255)
		set_msg_arg_int(RED,0,255)
		return PLUGIN_CONTINUE
	} else if(containi(message,"fury!") == strlen(message)-5) {
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(BLUE,0,128)
		set_msg_arg_int(GREEN,0,0)
		return PLUGIN_CONTINUE
	} else if(containi(message,"SPECIALIST!") == strlen(message)-11) {
		set_msg_arg_int(BLUE,0,0)
		set_msg_arg_int(RED,0,0)
		set_msg_arg_int(GREEN,0,0)
		return PLUGIN_CONTINUE
	} else if(containi(message,"The Specialist!") == strlen(message)-15) {
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(BLUE,0,128)
		set_msg_arg_int(GREEN,0,0)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Kung-Fu & Stuntman style!") == strlen(message)-26) {
		set_msg_arg_int(GREEN,0,128)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Knife & Stuntman style!") == strlen(message)-23) {
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(BLUE,0,255)
		set_msg_arg_int(GREEN,0,128)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Katana & Stuntman style!") == strlen(message)-24) {
		set_msg_arg_int(RED,0,64)
		set_msg_arg_int(BLUE,0,128)
		set_msg_arg_int(GREEN,0,128)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Stuntman style!") == strlen(message)-15) {
		set_msg_arg_int(BLUE,0,255)
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(GREEN,0,0)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Katana style!") == strlen(message)-13) {
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(GREEN,0,128)
		return PLUGIN_CONTINUE
	} else if(containi(message,"Knife style!") == strlen(message)-12) {
		set_msg_arg_int(BLUE,0,64)
		set_msg_arg_int(GREEN,0,128)
		return PLUGIN_CONTINUE
	}
	new kills = g_constkills[g_lastkill]
	if(kills < 12) set_msg_arg_int(RED,0,kills*20) && set_msg_arg_int(GREEN,0,255)
	else if(kills >= 12) set_msg_arg_int(RED,0,255) && set_msg_arg_int(GREEN,0,255-20*(kills-12))
	if(kills >= 25) {
		set_msg_arg_int(RED,0,255)
		set_msg_arg_int(GREEN,0,0)
	}
	return PLUGIN_CONTINUE
}

public hook_death(id) {
	new killer,dead
	killer = get_msg_arg_int(1)
	dead = get_msg_arg_int(2)
	g_constkills[dead] = 0
	g_constkills[killer] += 1
	g_lastkill = killer
	return PLUGIN_CONTINUE
}
/* AMXX-Studio Notes - DO NOT MODIFY BELOW HERE
*{\\ rtf1\\ ansi\\ deff0{\\ fonttbl{\\ f0\\ fnil Tahoma;}}\n\\ viewkind4\\ uc1\\ pard\\ lang1033\\ f0\\ fs16 \n\\ par }
*/
