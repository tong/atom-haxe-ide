package atom.haxe.ide;

import js.node.Fs;
import atom.CompositeDisposable;
import atom.haxe.ide.view.BuildLogView;
import atom.haxe.ide.view.StatusBarView;
import atom.haxe.ide.view.ServerLogView;

using StringTools;
using haxe.io.Path;

@:keep
class AtomPackage {

    static inline function __init__() untyped module.exports = atom.haxe.ide.AtomPackage;

    static var config = {
        server_port: {
            "title": "Server port",
            "description": "The port number the haxe server will wait on.",
            "type": "integer",
            "default": 7000
        },
        server_host: {
            "title": "Server host name",
            "description": "The ip adress the haxe server will listen.",
            "type": "string",
            "default": "127.0.0.1"
        },
        haxe_path: {
            "title": "Haxe executable path",
            "description": "Path to haxe",
            "type": "string",
            "default": "haxe"
        }
    };

    static var server : atom.haxe.ide.Server;
    static var subscriptions : CompositeDisposable;
    static var hxmlFile : String;

    static var log : BuildLogView;
    static var statusbar : StatusBarView;
    static var serverLog : ServerLogView;

    static var configChangeListener : Disposable;

    static function activate( savedState ) {

        trace( 'Atom-haxe-ide' );

        statusbar = new StatusBarView();
        log = new BuildLogView();
        serverLog = new ServerLogView();

        if( savedState.hxmlFile != null ) {
            if( fileExists( savedState.hxmlFile ) ) {
                hxmlFile = savedState.hxmlFile;
                trace(hxmlFile);
                /*
                var dir = new atom.Directory( hxmlFile.directory() );
                dir.onDidChange(function(){
                    trace("CHANGED");
                });
                */
                //trace(new atom.Directory('/home/tong/dev/tool/atom-haxe-ide/'));
                //js.node.Fs.watchFile('/home/tong/dev/tool/atom-haxe-ide/build.hxml',{persistent:true},handleFilechange);

                statusbar.setBuildPath( hxmlFile );
            }
        }
        if( hxmlFile == null ) {
            searchHxmlFiles(function(found){
                if( found.length > 0 ) {
                    hxmlFile = found[0];
                }
            });
        }

        server = new atom.haxe.ide.Server();
        server.onStart = function(){
            trace( 'Haxe server started' );
            statusbar.setServerStatus( server.exe, server.host, server.port, server.running );
        }
        server.onStop = function( code : Int ){
            trace( 'Haxe server stopped ($code)' );
        }
        server.onError = function(msg){
            trace( 'Haxe server error: $msg' );
            //Atom.notifications.addError( msg );
        }
        server.onMessage = function(msg){
            serverLog.add( msg );
            serverLog.scrollToBottom(); //TODO doesn't work
        }

        server.start(
            Atom.config.get( 'haxe-ide.haxe_path' ),
            Atom.config.get( 'haxe-ide.server_port' ),
            Atom.config.get( 'haxe-ide.server_host' ) );

        subscriptions = new CompositeDisposable();
        subscriptions.add( Atom.commands.add( 'atom-workspace', 'haxe:build', build ) );

        configChangeListener = Atom.config.onDidChange( 'haxe-c', {}, function(e){
            server.stop();
            server.start( e.newValue.haxe_path, e.newValue.server_port, e.newValue.server_host );
        });

        //Atom.commands.add( 'atom-workspace', 'haxe-c:toggle-server-log', toggleServerLog );
    }

    static function deactivate() {

        subscriptions.dispose();
        configChangeListener.dispose();

        server.stop();

        log.destroy();
        statusbar.destroy();
        serverLog.destroy();
    }

    static function serialize() {
        return {
            hxmlFile: hxmlFile
        };
    }

    ////////////////////////////////////////////////////////////////////////////

    static function build(e) {

        var selectedFile = getTreeViewFile();
        if( selectedFile != null && selectedFile.extension() == 'hxml' ) {
            hxmlFile = selectedFile;
        } else {
            if( hxmlFile == null ) {
                Atom.notifications.addWarning( 'No hxml file selected' );
                return;
            }
        }

        var dirPath = hxmlFile.directory();
        var filePath = hxmlFile.withoutDirectory();

        log.clear();
        statusbar.setBuildPath( hxmlFile );
        statusbar.setBuildStatus( active );

        var args = [ '--cwd', dirPath, filePath ];

        if( server.running ) {
            args.push( '--connect' );
            args.push( Std.string( server.port ) );
        }

        //args.push('--times'); //TODO
        //trace(args);

        var build = new Build();
        build.onMessage = function(msg){
            log.message( msg ).show();
        }
        build.onError = function(msg){

            statusbar.setBuildStatus( error );

            var haxeErrors = new Array<ErrorMessage>();
            for( line in msg.split( '\n' ) ) {
                line = line.trim();
                if( line.length == 0 )
                    continue;
                var err = ErrorMessage.parse( line );
                if( err != null ) {
                    haxeErrors.push( err );
                } else {
                    log.message( line, 'error' );
                }
            }

            if( haxeErrors.length > 0 ) {

                for( err in haxeErrors )
                    log.error( err );

                var err = haxeErrors[0];
                var filePath = err.path.startsWith('/') ? err.path : dirPath+'/'+err.path;
                var column =
                    if( err.lines != null ) err.lines.start;
                    else if( err.characters != null ) err.characters.start;
                    else err.character;

                Atom.workspace.open( filePath, {
                    initialLine: err.line - 1,
                    initialColumn: column,
                    activatePane: true,
                    searchAllPanes : true
                }).then( function(editor:TextEditor){

                    //TODO texteditor decoration

                    //var range = editor.getSelectedBufferRange();
                    var range = new atom.Range( [3,0],[4,5] );
                    var marker = editor.markBufferRange( range, { invalidate:'overlap' } );
                    var params : Dynamic = {  type:'line' };
                    Reflect.setField( params, 'class', 'haxe-error-decoration' );
                    // Why does the class fucking not apply ?????
                    var decoration = editor.decorateMarker( marker, params );
                });
            }

            log.show();

        }
        build.onSuccess = function() {
            statusbar.setBuildStatus( success );
        }
        build.start( args );
    }

    ////////////////////////////////////////////////////////////////////////////

    static function consumeStatusBar( bar ) {
        bar.addLeftTile( { item: statusbar.dom, priority:-10 } );
    }

    ////////////////////////////////////////////////////////////////////////////

    public static function provideServerService() {
        return {
            getStatus: function(){
                return { exe:server.exe, host:server.host, port:server.port, running:server.running };
            },
            start: function(){
                server.start(
                    Atom.config.get( 'haxe.haxe_path' ),
                    Atom.config.get( 'haxe.server_port' ),
                    Atom.config.get( 'haxe.server_host' ) );
            },
            stop: function(){
                server.stop();
            }
        };
    }

    public static function provideBuildService() {
        return {
            build : function( args:Array<String>, onMessage : String->Void, onError : String->Void, onSuccess : Void->Void ) {

                if( server.running ) {
                    args.push( '--connect' );
                    args.push( Std.string( server.port ) );
                }

                //TODO
                //_build();

                //log.clear();

                //var startTime = now();
                var build = new atom.haxe.Build();
                build.onMessage = onMessage;
                build.onError = function(msg){
                    //log.scrollToBottom();
                    onError( msg );
                };
                build.onSuccess = function() {
                    //trace(now()-startTime);
                    //log.scrollToBottom();
                    onSuccess();
                }
                build.start( args );
            }
        };
    }

    static function provideAutoCompletion() {
        //trace("provideAutoCompletion");
        //if( hxml != null )
        //return new CompletionProvider();
        return null;
    }

    ////////////////////////////////////////////////////////////////////////////

    static function fileExists( path : String ) : Bool {
		return try { Fs.accessSync(path); true; } catch (_:Dynamic) false;
	}

    static function getTreeViewFile() : String {
        return Atom.packages.getLoadedPackage( 'tree-view' ).serialize().selectedPath;
    }

    static function searchHxmlFiles( cb : Array<String>->Void ) {
        var paths = Atom.project.getPaths();
        (paths.length == 0) ? cb([]) : _searchHxmlFiles( paths, [], cb );
    }

    static function _searchHxmlFiles( paths : Array<String>, found : Array<String>, cb : Array<String>->Void ) {
        var path = paths.shift();
        Fs.readdir( path, function(err,files){
            for( f in files ) {
                if( f.extension() == 'hxml' )
                    found.push( '$path/$f' );
            }
            if( paths.length == 0 )
                cb( found );
            else
                _searchHxmlFiles( paths, found, cb );
        });
    }
}
