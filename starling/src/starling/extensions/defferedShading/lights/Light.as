package starling.extensions.defferedShading.lights
{
	import starling.display.DisplayObject;
	
	/**
	 * Base for all types of lights.
	 * Use one of the subclasses.
	 */
	public class Light extends DisplayObject
	{		
		public function Light(color:uint, strength:Number)
		{
			this.color = color;
			this.strength = strength;
		}
		
		/*-----------------------------
		Properties
		-----------------------------*/
		
		protected var _color:uint;
		protected var _colorR:Number;
		protected var _colorG:Number;
		protected var _colorB:Number;
		
		public function get color():uint
		{ 
			return _color;
		}
		public function set color(value:uint):void
		{
			_colorR = ((value >> 16) & 0xff) / 255.0;
			_colorG = ((value >>  8) & 0xff) / 255.0;
			_colorB = ( value        & 0xff) / 255.0;
			_color = value;
		}
		
		protected var _strength:Number;
		
		public function get strength():Number
		{ 
			return _strength;
		}
		public function set strength(value:Number):void
		{
			_strength = value;
		}	
	}
}