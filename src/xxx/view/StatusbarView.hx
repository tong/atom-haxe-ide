package xxx.view;

import js.Browser.document;
import js.html.Element;
import js.html.AnchorElement;
import js.html.DivElement;
import js.html.SpanElement;
import om.Time;
import atom.Disposable;
import atom.File;
import Atom.workspace;
import Atom.tooltips;

using haxe.io.Path;

class StatusbarView implements atom.Disposable {

	public var element(default,null) : DivElement;

	var icon : SpanElement;
    var info : AnchorElement;
    var meta : SpanElement;
	var contextMenu : Disposable;
	var tooltip : Disposable;
	var status : String;

	public function new() {

        element = document.createDivElement();
        element.classList.add( 'status-bar-xxx', 'inline-block' );

		icon = document.createSpanElement();
        icon.classList.add( 'icon-haxe' );
        element.appendChild( icon );

		info = document.createAnchorElement();
        info.classList.add( 'info' );
        element.appendChild( info );

        meta = document.createSpanElement();
        meta.classList.add( 'meta' );
        element.appendChild( meta );

		//IDE.project.on('dirty');

		IDE.server.onStart( function(){
			//trace("SAERVER STARZRTET");
			icon.classList.remove( 'off' );
			//meta.textContent = 'Server started';
			tooltip = tooltips.add( icon, { title: IDE.server.host + ':' + IDE.server.port } );
		});
		IDE.server.onStop( function(code){
			icon.classList.add( 'off' );
			//meta.textContent = 'Server stopped';
			if( tooltip != null ) tooltip.dispose();
		});
		IDE.server.onMessage( function(msg){
			meta.textContent = msg;
			//meta.textContent = 'Server stopped';
			if( tooltip != null ) tooltip.dispose();
		});

		if( IDE.server.running ) {
			tooltip = tooltips.add( icon, { title: IDE.server.host + ':' + IDE.server.port } );
			//icon.title = IDE.server.host + ':' + IDE.server.port;
		}

		var timeBuildStart : Float = null;

		IDE.build.on( 'start', function(_){
			//element.classList.add( 'active' );
			changeStatus( 'active' );
			timeBuildStart = Time.now();
		});
		IDE.build.on( 'message', function(msg){
			meta.textContent = msg;
		});
		IDE.build.on( 'error', function(err){
			//trace(err);
			//element.classList.add( 'error' );
		});
		IDE.build.on( 'end', function(code){

			if( code == 0 ) {
				changeStatus( 'success' );
			} else {
				changeStatus( 'error' );
			}

			var time = (Time.now() - timeBuildStart)/1000;
			var timeStr = Std.string( time );
			var cpos = timeStr.indexOf('.');
			meta.textContent = timeStr.substring( 0, cpos ) + timeStr.substring( cpos, 3 ) + 's';
		});

		//IDE.on('hxml_list_changed');

		IDE.build.on( 'hxml_select', changeHxml );
		changeHxml( IDE.build.hxml );

		info.addEventListener( 'click', handleClickInfo, false );
	}

	function changeHxml( hxml : File ) {
		if( hxml == null ) {
			icon.style.display = 'none';
			info.textContent = meta.textContent = '';
			if( contextMenu != null ) contextMenu.dispose();
		} else {
			icon.style.display = 'inline-block';
			var filePath = hxml.getPath();
			var parts = Atom.project.relativizePath( hxml.getPath() );
			if( parts[0] != null ) {
				var projectParts = parts[0].split( '/' );
				var str = projectParts[projectParts.length-1]+'/'+parts[1];
				info.textContent = str.withoutExtension();
			}
			meta.textContent = '';
			contextMenu = Atom.contextMenu.add({
				'.status-bar-xxx .info': [
					{ label: 'Build', command: 'haxe:build' }
					//{ label: 'Open', command: 'haxe:build' }
				]
			});
		}
	}

	function changeStatus( status : String ) {
		if( status != this.status ) {
			if( this.status != null ) {
                icon.classList.remove( this.status );
                info.classList.remove( this.status );
            }
			this.status = status;
            icon.classList.add( status );
            info.classList.add( status );
		}
		meta.textContent = '';
	}

	public function dispose() {
		info.removeEventListener( 'click', handleClickInfo );
		if( contextMenu != null ) contextMenu.dispose();
    }

	function handleClickInfo(e) {
        if( e.ctrlKey ) {
            IDE.build.start();
        } else {
            if( IDE.build.hxml != null ) workspace.open( IDE.build.hxml.getPath() );
        }
    }
}