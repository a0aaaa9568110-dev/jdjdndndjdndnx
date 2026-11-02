package states;

import flixel.FlxSubState;

import flixel.effects.FlxFlicker;
import lime.app.Application;

class FlashingState extends MusicBeatState
{
	public static var leftState:Bool = false;

	var texts:FlxTypedSpriteGroup<FlxText>;
	var bg:FlxSprite;

	override function create()
	{
		super.create();

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		texts = new FlxTypedSpriteGroup<FlxText>();
		texts.alpha = 0.0;
		add(texts);

		var warnText:FlxText = new FlxText(0, 0, FlxG.width,
			"Heads up! This JACOB build\n" +
			"This is only given to friends or people they trust\n" +
			"If you shouldn't be here, leave now. If you're a friend, go right ahead\n" +
			"and i love femboys");
		warnText.setFormat(Paths.font("hotline.ttf"), 24, FlxColor.WHITE, CENTER);
		warnText.screenCenter(Y);
		texts.add(warnText);

		FlxTween.tween(texts, {alpha: 1.0}, 0.5);
	}

	override function update(elapsed:Float)
	{
		if(leftState) {
			super.update(elapsed);
			return;
		}
		
		var back:Bool = controls.BACK;
		if (controls.ACCEPT || back) {
			leftState = true;
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			
			if(!back) {
				FlxG.sound.play(Paths.sound('confirmMenu'));
			} else {
				FlxG.sound.play(Paths.sound('cancelMenu'));
			}
			
			FlxTween.tween(texts, {alpha: 0}, 0.5, {
				onComplete: (_) -> MusicBeatState.switchState(new TitleState())
			});
		}
		
		super.update(elapsed);
	}
}
