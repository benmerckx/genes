import {default as Stats} from 'stats-js'
import {BitmapData} from '../dist/openfl/display/BitmapData'
import {Sprite} from '../dist/openfl/display/Sprite'
import {Tilemap} from '../dist/openfl/display/Tilemap'
import {Tileset} from '../dist/openfl/display/Tileset'
import {Event} from '../dist/openfl/events/Event'
import {MouseEvent} from '../dist/openfl/events/MouseEvent'
import Bunny from './Bunny'

export class Main extends Sprite {
	
	
	private addingBunnies:boolean;
	private bunnies:Array<Bunny>;
	private gravity:number;
	private minX:number;
	private minY:number;
	private maxX:number;
	private maxY:number;
	private stats:Stats;
	private tilemap:Tilemap;
	private tileset:Tileset;
	
	
	constructor () {
		
		super ();
		
		this.bunnies = [];
		
		BitmapData.loadFromFile ("wabbit_alpha.png")
			.onComplete ((bitmapData) => this.start (bitmapData))
			.onError ((e) => console.error (e));
		
	}
	
	
	private start (bitmapData:BitmapData):void {
		
		this.minX = 0;
		this.maxX = this.stage.stageWidth;
		this.minY = 0;
		this.maxY = this.stage.stageHeight;
		this.gravity = 0.5;
		
		this.tileset = new Tileset (bitmapData);
		this.tileset.addRect (bitmapData.rect);
		
		this.tilemap = new Tilemap (this.stage.stageWidth, this.stage.stageHeight, this.tileset);
		//this.tilemap.tileAlphaEnabled = false;
		//this.tilemap.tileColorTransformEnabled = false;
		this.addChild (this.tilemap);
		
		this.stats = new Stats ();
		this.stats.domElement.style.position = 'absolute';
		this.stats.domElement.style.left = '0px';
		this.stats.domElement.style.top = '0px';
		document.body.appendChild (this.stats.domElement);
		
		this.stage.addEventListener (MouseEvent.MOUSE_DOWN, this.stage_onMouseDown);
		this.stage.addEventListener (MouseEvent.MOUSE_UP, this.stage_onMouseUp);
		this.stage.addEventListener (Event.ENTER_FRAME, this.stage_onEnterFrame);
		
		for (var i = 0; i < 10; i++) {
			
			this.addBunny ();
			
		}
		
	}
	
	
	private addBunny ():void {
		
		var bunny = new Bunny ();
		bunny.x = 0;
		bunny.y = 0;
		bunny.speedX = Math.random () * 5;
		bunny.speedY = (Math.random () * 5) - 2.5;
		this.bunnies.push (bunny);
		this.tilemap.addTile (bunny);
		
	}
	
	
	
	
	// Event Handlers
	
	
	
	
	stage_onEnterFrame = (event:Event) => {
		
		this.stats.begin ();
		
		for (var i = 0; i < this.bunnies.length; i++) {
			
			var bunny = this.bunnies[i];
			bunny.x += bunny.speedX;
			bunny.y += bunny.speedY;
			bunny.speedY += this.gravity;
			
			if (bunny.x > this.maxX) {
				
				bunny.speedX *= -1;
				bunny.x = this.maxX;
				
			} else if (bunny.x < this.minX) {
				
				bunny.speedX *= -1;
				bunny.x = this.minX;
				
			}
			
			if (bunny.y > this.maxY) {
				
				bunny.speedY *= -0.8;
				bunny.y = this.maxY;
				
				if (Math.random () > 0.5) {
					
					bunny.speedY -= 3 + Math.random () * 4;
					
				}
				
			} else if (bunny.y < this.minY) {
				
				bunny.speedY = 0;
				bunny.y = this.minY;
				
			}
			
		}
		
		if (this.addingBunnies) {
			
			for (var i = 0; i < 100; i++) {
				
				this.addBunny ();
				
			}
			
		}
		
		this.stats.end ();
		
	}
	
	
	private stage_onMouseDown = (event:MouseEvent) => {
		
		this.addingBunnies = true;
		
	}
	
	
	private stage_onMouseUp = (event:MouseEvent) => {
		
		this.addingBunnies = false;
		console.log (this.bunnies.length + " bunnies");
		
	}
	
	
}


export default Main;