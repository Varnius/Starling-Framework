package starling.extensions.deferredShading
{
	import starling.textures.Texture;

	public class MaterialProperties
	{
		public static const SPECULAR_POWER_SCALE:Number = 256.0;
		public static const SPECULAR_INTENSITY_SCALE:Number = 50.0;
		
		public static const DEFAULT_SPECULAR_POWER:Number = 10.0;
		public static const DEFAULT_SPECULAR_INTENSITY:Number = 3.0;
		
		public var normalMap:Texture;
		public var depthMap:Texture;
		public var specularMap:Texture;
		public var specularIntensity:Number = DEFAULT_SPECULAR_INTENSITY;
		public var specularPower:Number = DEFAULT_SPECULAR_POWER;
		
		public function MaterialProperties(normalMap:Texture = null, depthMap:Texture = null, specularMap:Texture = null)
		{
			this.normalMap = normalMap;
			this.depthMap = depthMap;
			this.specularMap = specularMap;
		}
	}
}