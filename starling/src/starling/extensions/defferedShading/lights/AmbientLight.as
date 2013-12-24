package starling.extensions.defferedShading.lights
{
	import flash.geom.Rectangle;
	
	import starling.core.RenderSupport;
	import starling.display.DisplayObject;

	/**
	 * Represents an even amount of light, added to each pixel on the screen. 
	 */
	public class AmbientLight extends Light
	{
		private var bounds:Rectangle = new Rectangle();
		
		public function AmbientLight(color:uint, strength:Number)
		{
			super(color, strength);
		}
		
		override public function render(support:RenderSupport, parentAlpha:Number):void
		{
			// ..
		}
		
		public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
		{
			return bounds;
		}
	}
}