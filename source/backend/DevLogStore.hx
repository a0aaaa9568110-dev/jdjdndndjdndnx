package backend;

import haxe.Log;
import openfl.Lib;
import openfl.events.UncaughtErrorEvent;

/**
 * Data store for DevLogState.
 * Always compiled in (debug AND release builds).
 *
 * Call DevLogStore.init() once in Main.hx after the FlxGame is added.
 */
class DevLogStore
{
	public static var luaErrors:Array<String> = [];
	public static var traces:Array<String> = [];
	public static var errors:Array<String> = [];
	public static var events:Array<String> = [];
	public static var watches:Map<String, Void->Dynamic> = new Map();

	static var inited:Bool = false;

	public static inline function stamp():String
		return DateTools.format(Date.now(), "%H:%M:%S");

	static function push(arr:Array<String>, s:String, max:Int)
	{
		arr.push(stamp() + "  " + s);
		if (arr.length > max) arr.shift();
	}

	/** Called from FunkinLua.luaTrace */
	public static function addLua(msg:String)
	{
		push(luaErrors, msg, 300);
	}

	/** Log a custom timeline event: DevLogStore.event("boss spawned"); */
	public static function event(msg:String)
	{
		push(events, msg, 300);
	}

	/** Live watch a value: DevLogStore.watch("health", () -> PlayState.instance.health); */
	public static function watch(name:String, getter:Void->Dynamic)
	{
		watches.set(name, getter);
	}

	public static function unwatch(name:String)
	{
		watches.remove(name);
	}

	public static function init()
	{
		if (inited) return;
		inited = true;

		// capture every trace() in the whole game
		var oldTrace = Log.trace;
		Log.trace = function(v:Dynamic, ?infos:haxe.PosInfos)
		{
			var where = infos != null ? infos.fileName + ":" + infos.lineNumber + "  " : "";
			push(traces, where + Std.string(v), 600);
			oldTrace(v, infos);
		};

		// capture uncaught errors
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function(e:UncaughtErrorEvent)
		{
			push(errors, "UNCAUGHT: " + Std.string(e.error), 100);
		});

		// auto log state switches
		flixel.FlxG.signals.postStateSwitch.add(function()
		{
			event("State -> " + Type.getClassName(Type.getClass(flixel.FlxG.state)));
		});

		// default watches
		watch("State", () -> Type.getClassName(Type.getClass(flixel.FlxG.state)));
		watch("timeScale", () -> flixel.FlxG.timeScale);
		watch("volume", () -> flixel.FlxG.sound.volume);
		watch("mouse", () -> Std.int(flixel.FlxG.mouse.x) + ", " + Std.int(flixel.FlxG.mouse.y));
		watch("music time (ms)", () -> flixel.FlxG.sound.music != null ? Math.round(flixel.FlxG.sound.music.time) : "no music");
		watch("camera zoom", () -> flixel.FlxG.camera.zoom);

		event("DevLogStore started");
	}
}
