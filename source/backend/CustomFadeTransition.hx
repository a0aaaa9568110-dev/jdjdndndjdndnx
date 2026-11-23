package backend;

import flixel.util.FlxGradient;
import flixel.graphics.FlxGraphic;
import haxe.Json;

typedef TransitionSettings = {
	var enabled:Bool;
	var type:String; // "fade" or "stickers"
	var stickerPack:String;
	var showTransIn:Bool;
	var showTransOut:Bool;
	var color:FlxColor;
	var durationMultiplier:Float;
	var disabledStates:Array<String>;
}

typedef StickerLayout = {
	var path:String;
	var x:Float;
	var y:Float;
	var angle:Float;
	var scale:Float;
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

	// Sticker mode
	static inline var STICKER_SPAN:Float = 0.9; // seconds for all stickers to land (before multiplier)
	static inline var STICKER_FRAME:Float = 1 / 24;
	var useStickers:Bool = false;
	var stickerPack:StickerPack;
	var stickers:Array<StickerSprite> = [];
	var stickerTime:Float = 0;
	var stickerIndex:Int = 0;
	var stickersDone:Bool = false;

	// The sticker layout from the fade-out is reused by the next state's fade-in,
	// so the same stickers that covered the screen are the ones that peel away.
	static var savedLayout:Array<StickerLayout> = null;
	static var savedLayoutPack:String = null;

	/**
	 * Runtime choice of transition style: "fade", "stickers", or null to use the JSON's "type".
	 * Set this from an options menu or a script, e.g. CustomFadeTransition.typeOverride = 'stickers';
	 */
	public static var typeOverride:String = null;

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
	 * Forces data/transitionSettings.json (and sticker packs) to be read again.
	 * Call this if you edit the files at runtime or switch mods manually.
	 */
	public static function reloadSettings():Void
	{
		settings = loadSettings();
		loadedMod = currentMod();
		StickerPack.clearCache();
		savedLayout = null;
		savedLayoutPack = null;
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
			type: 'fade',
			stickerPack: 'default',
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

						if(Reflect.hasField(json, 'type'))
						{
							var type:String = Std.string(json.type).toLowerCase();
							if(type == 'fade' || type == 'stickers')
								s.type = type;
						}

						if(Reflect.hasField(json, 'stickerPack'))
						{
							var pack:String = Std.string(json.stickerPack);
							if(pack.length > 0)
								s.stickerPack = pack;
						}

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

	/** The runtime override wins over the JSON; anything unrecognized falls back to the JSON value. */
	static function getActiveType(s:TransitionSettings):String
	{
		if(typeOverride != null)
		{
			var type:String = typeOverride.toLowerCase();
			if(type == 'fade' || type == 'stickers')
				return type;
		}
		return s.type;
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

		cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];

		// If the sticker pack is missing or unusable, fall back to the normal fade
		useStickers = (getActiveType(s) == 'stickers') && createStickers(s);
		if(!useStickers)
			createFade(s);

		super.create();
	}

	// ---------------------------------------------------------------- FADE

	function createFade(s:TransitionSettings):Void
	{
		transColor = s.color;
		duration *= s.durationMultiplier;

		// Same color with zero alpha, so tinted fades don't pass through grey/black
		var clear:FlxColor = FlxColor.fromRGB(transColor.red, transColor.green, transColor.blue, 0);

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
	}

	function updateFade(elapsed:Float):Void
	{
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

	// ------------------------------------------------------------ STICKERS

	/** Returns false if stickers can't be used (so the caller falls back to the fade). */
	function createStickers(s:TransitionSettings):Bool
	{
		stickerPack = StickerPack.fetch(s.stickerPack);
		if(stickerPack == null)
			return false;

		var layout:Array<StickerLayout> = null;
		if(isTransIn && savedLayout != null && savedLayoutPack == s.stickerPack)
			layout = savedLayout;
		else
			layout = buildStickerLayout();

		if(layout == null || layout.length == 0)
			return false;

		// Fade-out saves its layout for the next state's fade-in; fade-in consumes it
		if(isTransIn)
		{
			savedLayout = null;
			savedLayoutPack = null;
		}
		else
		{
			savedLayout = layout;
			savedLayoutPack = s.stickerPack;
		}

		var span:Float = STICKER_SPAN * s.durationMultiplier;
		for(i in 0...layout.length)
		{
			var l:StickerLayout = layout[i];
			var sticker:StickerSprite = new StickerSprite(l.x, l.y, l.path);
			sticker.angle = l.angle;
			sticker.targetScale = l.scale;
			sticker.timing = FlxMath.remapToRange(i, 0, layout.length, 0, span);

			// Fade-in starts fully covered; fade-out starts empty
			sticker.visible = isTransIn;
			if(isTransIn)
				sticker.scale.set(l.scale, l.scale);

			stickers.push(sticker);
			add(sticker);
		}
		return true;
	}

	/**
	 * Places stickers in a loose grid over the whole screen, shuffles the order they land in,
	 * then finishes with one sticker dead-center.
	 */
	function buildStickerLayout():Array<StickerLayout>
	{
		final zoom:Float = Math.max(camera.zoom, 0.001);
		final areaW:Float = FlxG.width / zoom;
		final areaH:Float = FlxG.height / zoom;
		final left:Float = (FlxG.width - areaW) / 2;
		final top:Float = (FlxG.height - areaH) / 2;
		final right:Float = left + areaW;
		final bottom:Float = top + areaH;

		var layout:Array<StickerLayout> = [];
		var xPos:Float = left - 100;
		var yPos:Float = top - 100;
		while(xPos <= right)
		{
			var path:String = stickerPack.getRandomStickerPath();
			var graphic:FlxGraphic = Paths.image(path);
			var w:Float = (graphic != null) ? graphic.width : 200;

			layout.push({
				path: path,
				x: xPos,
				y: yPos,
				angle: FlxG.random.int(-60, 70),
				scale: FlxG.random.float(0.97, 1.02)
			});

			xPos += Math.max(w * 0.5, 20);
			if(xPos >= right && yPos <= bottom)
			{
				xPos = left - 100;
				yPos += FlxG.random.float(70, 120);
			}
		}
		FlxG.random.shuffle(layout);

		// The very last sticker sits in the center of the screen
		var lastPath:String = stickerPack.getRandomStickerPath();
		var lastGraphic:FlxGraphic = Paths.image(lastPath);
		var lastW:Float = (lastGraphic != null) ? lastGraphic.width : 0;
		var lastH:Float = (lastGraphic != null) ? lastGraphic.height : 0;
		layout.push({
			path: lastPath,
			x: (FlxG.width - lastW) / 2,
			y: (FlxG.height - lastH) / 2,
			angle: 0,
			scale: FlxG.random.float(0.97, 1.02)
		});

		return layout;
	}

	function playStickerSound():Void
	{
		var key:Null<String> = stickerPack.getRandomSound();
		if(key != null)
			FlxG.sound.play(Paths.sound(key));
	}

	function updateStickers(elapsed:Float):Void
	{
		if(stickersDone) return;

		stickerTime += elapsed;
		final lastIndex:Int = stickers.length - 1;

		while(stickerIndex < stickers.length && stickerTime >= stickers[stickerIndex].timing)
		{
			var sticker:StickerSprite = stickers[stickerIndex];
			if(isTransIn)
			{
				sticker.visible = false;
			}
			else
			{
				sticker.visible = true;
				// Each sticker pops to its final scale 0-2 frames (at 24fps) after appearing.
				// The last one always waits the full 2 frames so it gets to "pop".
				var frames:Int = (stickerIndex == lastIndex) ? 2 : FlxG.random.int(0, 2);
				sticker.popTime = stickerTime + STICKER_FRAME * frames;
			}
			playStickerSound();
			stickerIndex++;
		}

		if(isTransIn)
		{
			if(stickerIndex >= stickers.length)
				finishStickers();
			return;
		}

		for(sticker in stickers)
		{
			if(sticker.popTime >= 0 && stickerTime >= sticker.popTime)
			{
				sticker.scale.set(sticker.targetScale, sticker.targetScale);
				sticker.popTime = -1;
			}
		}

		// Screen is fully covered and the last sticker has popped: hand over to the next state
		if(stickerIndex >= stickers.length && stickers[lastIndex].popTime < 0)
			finishStickers();
	}

	function finishStickers():Void
	{
		stickersDone = true;
		close();
	}

	// -------------------------------------------------------------- UPDATE

	override function update(elapsed:Float) {
		super.update(elapsed);

		if(!transitionEnabled)
		{
			close();
			return;
		}

		if(useStickers)
			updateStickers(elapsed);
		else
			updateFade(elapsed);
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

/**
 * A single sticker used by CustomFadeTransition's "stickers" mode.
 */
class StickerSprite extends FlxSprite
{
	/** Seconds into the transition at which this sticker appears / disappears. */
	public var timing:Float = 0;

	/** Time (in transition seconds) at which the "pop" scale is applied. -1 = nothing pending. */
	public var popTime:Float = -1;

	/** The slightly randomized scale this sticker settles on. */
	public var targetScale:Float = 1;

	public function new(x:Float, y:Float, key:String)
	{
		super(x, y);

		var graphic:FlxGraphic = Paths.image(key);
		if(graphic != null)
			loadGraphic(graphic);

		updateHitbox();
		scrollFactor.set();
		antialiasing = ClientPrefs.data.antialiasing;
	}
}

/**
 * A sticker pack loaded from data/stickerpacks/<id>.json
 *
 * {
 *   "version": "1.0.0",
 *   "name": "My Stickers",
 *   "artist": "Someone",
 *   "stickers": ["stickers/sticker1", "stickers/sticker2"],      // image keys (images/<key>.png)
 *   "sounds":   ["stickersounds/click1", "stickersounds/click2"] // optional (sounds/<key>.ogg)
 * }
 *
 * Entries that point to files that don't exist are ignored.
 */
class StickerPack
{
	static var cache:Map<String, Null<StickerPack>> = new Map();

	public final id:String;
	public var name:String = '';
	public var artist:String = '';
	public var stickers:Array<String> = [];
	public var sounds:Array<String> = [];

	/** Returns the pack with this ID, or null if it is missing / has no usable stickers. */
	public static function fetch(id:String):Null<StickerPack>
	{
		if(cache.exists(id))
			return cache.get(id);

		var pack:Null<StickerPack> = load(id);
		cache.set(id, pack);
		return pack;
	}

	public static function clearCache():Void
	{
		cache.clear();
	}

	static function load(id:String):Null<StickerPack>
	{
		try
		{
			var path:String = 'data/stickerpacks/$id.json';
			if(!Paths.fileExists(path, TEXT))
			{
				trace('Sticker pack not found: $path');
				return null;
			}

			var raw:String = Paths.getTextFromFile(path);
			if(raw == null || raw.length == 0)
				return null;

			var pack:StickerPack = new StickerPack(id, Json.parse(raw));
			if(pack.stickers.length == 0)
			{
				trace('Sticker pack "$id" has no usable stickers (check the image paths).');
				return null;
			}
			return pack;
		}
		catch(e:Dynamic)
		{
			trace('Failed to load sticker pack "$id": $e');
		}
		return null;
	}

	function new(id:String, data:Dynamic)
	{
		this.id = id;

		if(Reflect.hasField(data, 'name')) name = Std.string(data.name);
		if(Reflect.hasField(data, 'artist')) artist = Std.string(data.artist);

		for(key in readStrings(data.stickers))
		{
			if(Paths.fileExists('images/$key.png', IMAGE))
				stickers.push(key);
			else
				trace('Sticker pack "$id": missing image "$key"');
		}

		for(key in readStrings(data.sounds))
		{
			if(Paths.fileExists('sounds/$key.${Paths.SOUND_EXT}', SOUND))
				sounds.push(key);
			else
				trace('Sticker pack "$id": missing sound "$key"');
		}
	}

	static function readStrings(value:Dynamic):Array<String>
	{
		var out:Array<String> = [];
		if(value != null && Std.isOfType(value, Array))
		{
			var list:Array<Dynamic> = value;
			for(entry in list)
				out.push(Std.string(entry));
		}
		return out;
	}

	public function getRandomStickerPath():String
	{
		return FlxG.random.getObject(stickers);
	}

	public function getRandomSound():Null<String>
	{
		return sounds.length > 0 ? FlxG.random.getObject(sounds) : null;
	}

	public function toString():String
	{
		return 'StickerPack($id)';
	}
}
