package backend;

import flixel.util.FlxGradient;
import haxe.Json;

typedef TransitionSettings = {
	var enabled:Bool;
	var showTransIn:Bool;
	var showTransOut:Bool;
	var color:FlxColor;
	var durationMultiplier:Float;
	var disabledStates:Array<String>;
}

class CustomFadeTransition extends MusicBeatSubstate {
	public static var finishCallback:Void->Void;
	var isTransIn:Bool = false;
	var transBlack:FlxSprite;
	var transGradient:FlxSprite;

	var duration:Float;

	// Resolved per-transition from data/transitionSettings.json
	var transitionEnabled:Bool = true;
	var transColor:FlxColor = FlxColor.BLACK;

	// Cached settings (loaded once, reloaded when the active mod changes)
	static var settings:TransitionSettings = null;
	static var loadedMod:String = null;

	public function new(duration:Float, isTransIn:Bool)
	{
		this.duration = duration;
		this.isTransIn = isTransIn;
		super();
	}

	/**
	 * Forces data/transitionSettings.json to be read again.
	 * Call this if you edit the file at runtime or switch mods manually.
	 */
	public static function reloadSettings():Void
	{
		settings = loadSettings();
		loadedMod = currentMod();
	}

	static function currentMod():String
	{
		#if MODS_ALLOWED
		return Mods.currentModDirectory;
		#else
		return '';
		#end
	}

	static function getSettings():TransitionSettings
	{
		// Reload automatically the first time and whenever the mod changes
		if(settings == null || loadedMod != currentMod())
			reloadSettings();
		return settings;
	}

	static function getDefaults():TransitionSettings
	{
		return {
			enabled: true,
			showTransIn: true,
			showTransOut: true,
			color: FlxColor.BLACK,
			durationMultiplier: 1.0,
			disabledStates: []
		};
	}

	/**
	 * Reads data/transitionSettings.json (mods folder first, then assets).
	 * Any missing or invalid field falls back to its default.
	 */
	static function loadSettings():TransitionSettings
	{
		var s:TransitionSettings = getDefaults();
		try
		{
			var path:String = 'data/transitionSettings.json';
			if(Paths.fileExists(path, TEXT))
			{
				var raw:String = Paths.getTextFromFile(path);
				if(raw != null && raw.length > 0)
				{
					var json:Dynamic = Json.parse(raw);
					if(json != null)
					{
						if(Reflect.hasField(json, 'enabled'))
							s.enabled = json.enabled != false;
						if(Reflect.hasField(json, 'showTransIn'))
							s.showTransIn = json.showTransIn != false;
						if(Reflect.hasField(json, 'showTransOut'))
							s.showTransOut = json.showTransOut != false;

						if(Reflect.hasField(json, 'color'))
							s.color = parseColor(json.color, s.color);

						if(Reflect.hasField(json, 'durationMultiplier'))
						{
							var mult:Float = Std.parseFloat(Std.string(json.durationMultiplier));
							if(!Math.isNaN(mult) && mult >= 0)
								s.durationMultiplier = mult;
						}

						if(Reflect.hasField(json, 'disabledStates') && Std.isOfType(json.disabledStates, Array))
						{
							var list:Array<Dynamic> = json.disabledStates;
							for(entry in list)
								s.disabledStates.push(Std.string(entry));
						}
					}
				}
			}
		}
		catch(e:Dynamic)
		{
			trace('Failed to load transitionSettings.json: $e');
			s = getDefaults();
		}
		return s;
	}

	/** Accepts "0xFF000000", "#FFFFFF", "0x000000", color names ("RED"), or a raw number. */
	static function parseColor(value:Dynamic, fallback:FlxColor):FlxColor
	{
		if(value == null) return fallback;
		if(Std.isOfType(value, Int)) return FlxColor.fromInt(cast value);

		var parsed:Null<FlxColor> = FlxColor.fromString(Std.string(value));
		return parsed != null ? parsed : fallback;
	}

	/** Matches either the full class name ("states.PlayState") or the short one ("PlayState"). */
	static function isStateDisabled(list:Array<String>):Bool
	{
		if(list.length == 0 || FlxG.state == null) return false;

		var full:String = Type.getClassName(Type.getClass(FlxG.state));
		var short:String = full.substr(full.lastIndexOf('.') + 1);
		for(name in list)
		{
			if(name == full || name == short)
				return true;
		}
		return false;
	}

	override function create()
	{
		var s:TransitionSettings = getSettings();

		transitionEnabled = s.enabled
			&& (isTransIn ? s.showTransIn : s.showTransOut)
			&& !isStateDisabled(s.disabledStates);

		// Transition hidden: build nothing, update() will close it right away
		if(!transitionEnabled)
		{
			super.create();
			return;
		}

		transColor = s.color;
		duration *= s.durationMultiplier;

		// Same color with zero alpha, so tinted fades don't pass through grey/black
		var clear:FlxColor = FlxColor.fromRGB(transColor.red, transColor.green, transColor.blue, 0);

		cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];
		var width:Int = Std.int(FlxG.width / Math.max(camera.zoom, 0.001));
		var height:Int = Std.int(FlxG.height / Math.max(camera.zoom, 0.001));
		transGradient = FlxGradient.createGradientFlxSprite(1, height, (isTransIn ? [clear, transColor] : [transColor, clear]));
		transGradient.scale.x = width;
		transGradient.updateHitbox();
		transGradient.scrollFactor.set();
		transGradient.screenCenter(X);
		add(transGradient);

		transBlack = new FlxSprite().makeGraphic(1, 1, transColor);
		transBlack.scale.set(width, height + 400);
		transBlack.updateHitbox();
		transBlack.scrollFactor.set();
		transBlack.screenCenter(X);
		add(transBlack);

		if(isTransIn)
			transGradient.y = transBlack.y - transBlack.height;
		else
			transGradient.y = -transGradient.height;

		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if(!transitionEnabled)
		{
			close();
			return;
		}

		final height:Float = FlxG.height * Math.max(camera.zoom, 0.001);
		final targetPos:Float = transGradient.height + 50 * Math.max(camera.zoom, 0.001);
		if(duration > 0)
			transGradient.y += (height + targetPos) * elapsed / duration;
		else
			transGradient.y = (targetPos) * elapsed;

		if(isTransIn)
			transBlack.y = transGradient.y + transGradient.height;
		else
			transBlack.y = transGradient.y - transBlack.height;

		if(transGradient.y >= targetPos)
		{
			close();
		}
	}

	// Don't delete this
	override function close():Void
	{
		super.close();

		if(finishCallback != null)
		{
			finishCallback();
			finishCallback = null;
		}
	}
}
