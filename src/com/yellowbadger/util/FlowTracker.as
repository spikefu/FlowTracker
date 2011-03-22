package com.yellowbadger.util
{
	import com.adobe.cairngorm.commands.ICommand;
	import com.adobe.cairngorm.control.CairngormEvent;
	
	import flash.desktop.Clipboard;
	import flash.desktop.ClipboardFormats;
	import flash.display.DisplayObject;
	import flash.events.ContextMenuEvent;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.system.System;
	import flash.ui.Keyboard;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getTimer;
	
	import mx.core.Application;
	import mx.formatters.DateFormatter;
	import mx.managers.SystemManager;
	import mx.messaging.events.MessageAckEvent;
	import mx.messaging.events.MessageEvent;
	import mx.rpc.events.ResultEvent;
	import mx.rpc.remoting.Operation;
	
	import org.spicefactory.lib.reflect.Method;
	import org.spicefactory.parsley.popup.CairngormPopUpSupport;
	
	public class FlowTracker
	{
		
		public static var on:Boolean = true;
		
		public static var showHints:Boolean = false;
		
		public static var showTimes:Boolean = true;
		
		public static var showPackageNames:Boolean = false;
		
		public static var showCaller:Boolean = true;
		
		public static var maxLogsToKeep:int = 30;
		
		public static var logToConsole:Boolean = true;
		
		public static var beginToken:String = ">";
		
		public static var endToken:String = "<";
		
		public static var markToken:String = "+";
		
		public static var indentToken:String = "-";
		
		public static var endFlowToken:String = "";
		
		public static var beginFlowToken:String = "";
		
		public static var logDirectory:String = "flowTracker";
		
		public static var logExternal:Function = logToFile; 
		
		public static var stackFilters:Array = ["com.yellowbadger.","spicefactory","flash.","mx.","/builtin","NetConnectionMessageResponder","SetIntervalTimer/onTimer","ParsleyEventHelper"];
		
		private static var indent:String = "";
		
		private static var _instance:FlowTracker = new FlowTracker();
		
		private static var indicatorToken:String = "";
		
		private static var currentStack:Array = [];
		
		private static var timeOffset:int = 0;
		
		private static var callDepth:int = 0;
		
		private static var dateFormatter:DateFormatter = new DateFormatter();
		
		private static var fileStream:FileStream;
		
		public static var initialized:Boolean = initialize();
		
		private static var prevKeystroke:String;
		
		public static function instance():FlowTracker {
			return _instance;
		}
		
		public static function initialize():Boolean {
			(Application.application.systemManager as SystemManager).addEventListener(MouseEvent.CLICK,onMouseEvent,true,int.MAX_VALUE);
			(Application.application.systemManager as SystemManager).addEventListener(KeyboardEvent.KEY_DOWN,onKeyboardEvent,true,int.MAX_VALUE);
			
			cleanLogs();
			return true;
		}
		
		private static function onMouseEvent(event:MouseEvent):void {
			if (!on) {
				return;
			}
			if (event.target) {
				var id:String = "";
				var path:String = getClassName(event.target);
				var parent:DisplayObject = event.target.parent;
				while (id == "" && parent != null) {
					parent = parent.parent;
					if (parent == null) {
						break;
					}
					path = getClassName(parent) + "/" + path
					if (parent.hasOwnProperty("id") && parent["id"] != null) {
						id = parent["id"];
					}
				}
				mark("Click " + path + " (" + id + ")");
			}
		}
		
		private static function keyName(keyCode:int):String {
			switch (keyCode) {
				case Keyboard.ENTER:
					return "Enter";
				case Keyboard.TAB:
					return "tab";
			}
			return keyCode.toString();
		}
		
		private static function onKeyboardEvent(event:KeyboardEvent):void {
			if (!on) {
				return;
			}
			if (event.keyCode == Keyboard.CONTROL 
				|| event.keyCode == Keyboard.SHIFT
				|| event.keyCode == Keyboard.ALTERNATE) {
				return;
			}
			if (event.charCode > 32) {
				if (event.ctrlKey && String.fromCharCode(event.charCode) == "v") {
					mark("Paste: " + Clipboard.generalClipboard.getData(ClipboardFormats.TEXT_FORMAT));
				}
				if (prevKeystroke == null) {
					prevKeystroke = "";
				}
				prevKeystroke += String.fromCharCode(event.charCode);
			} else {
				checkForTyping();
				mark("Keystroke: " + keyName(event.keyCode));
			}
			
		}
		
		private static function checkForTyping():void {
			if (prevKeystroke != null) {
				var typing:String = prevKeystroke;
				prevKeystroke = null;
				mark("Typing: " + typing);
			}
		}
		
		public static function begin(message:Object):void {
			if (!on) {
				return;
			}
			checkForTyping();
			if (callDepth == 0) {
				timeOffset = getTimer();
				log(beginFlowToken);
				log(formatDate(new Date()));
			}
			callDepth++;
			indicatorToken = beginToken;
			track(message);
		}
		
		
		public static function end(message:Object):void {
			if (!on) {
				return;
			}
			checkForTyping();
			indicatorToken = endToken;
			track(message);
			callDepth--;
			if (callDepth < 0) {
				log("FlowTracker is out of whack! callDepth is less than 0 (" + callDepth + ")");
			}
			if (callDepth == 0) {
				log(formatDate(new Date()));
				log(endFlowToken);
				timeOffset = 0;
			}
		}
		
		public static function mark(message:Object):void {
			checkForTyping();
			indicatorToken = markToken;
			track(message);
		}
		
		private static function getCaller():String{
			var foo:Date;
			try {
				var bar:* = foo.getDate();
			} catch (e:Error) {
				var stack:Array = e.getStackTrace().split("\n");
				var source:String;
				for each (var element:String in stack) {
					if (element.indexOf("\tat") >= 0) {
						var skip:Boolean = false;
						for each (var filter:String in stackFilters) {
							if (element.indexOf(filter) >= 0) {
								skip =  true;
								break;
							}
						}
						if (skip) {
							continue;
						}
						return getFileAndLineNumber(element);
					}
				}
			}
			return "";
		}
		
		private static function getFileAndLineNumber(str:String):String {
			var pathIndex:int = str.lastIndexOf("\\");
			if (str.lastIndexOf("/") > pathIndex) {
				pathIndex = str.lastIndexOf("/");
			}
			str = str.substring(pathIndex+1,str.length-1);
			return str;
		}
		
		private static function track(message:Object):void {
			updateIndentString();
			if (message is Method) {
				trackMethod(message as Method,callDepth)
			} else if (message is CairngormEvent) { 
				trackCairngormEvent(message as CairngormEvent);
			}  else if (message is ICommand) { 
				trackCairngormCommand(message as ICommand);
			} else if (message is ResultEvent) { 
				trackResultEvent(message as ResultEvent);
			} else if (message is Event) { 
				trackFlashEvent(message as Event);
			}  else if (message is Operation) { 
				trackOperation(message as Operation);
			} else {
				append(message.toString(),"");
			}
		}
		
		
		private static function trackMethod(method:Method,layer:int):void {
			if (method.name.indexOf("interceptContextMessages") >= 0) {
				return;
			}
			var hint:String = " (invoked)";
			if (indicatorToken == endToken) {
				hint = " (completed)";
			}
			append(indent + removePackageName(method.owner.name) + "." + method.name + "()", hint);
		}
		
		private static function trackFlashEvent(event:Event):void {
			var hint:String = " (dispatched)";
			if (indicatorToken == endToken) {
				hint = " (processed)";
			}
			append(indent + getClassName(event) + "." + event.type, hint);
		}
		
		private static function trackResultEvent(event:ResultEvent):void {
			var hint:String = " (received)";
			if (indicatorToken == endToken) {
				hint = " (processed)";
			}
			append(indent + getClassName(event) + " " + getClassName(event.result), hint);
		}
		
		private static function trackOperation(operation:Operation):void {
			var hint:String = " (sent)";
			append(indent + operation.service.destination + "." + operation.name + "()", hint);
		}
		
		private static function trackCairngormEvent(event:CairngormEvent):void {
			var hint:String = " (dispatched)";
			if (indicatorToken == endToken) {
				hint = " (processed)";
			}
			append(indent + getClassName(event) + "." + event.type, hint);
		}
		
		private static function trackCairngormCommand(command:ICommand):void {
			var hint:String = " (invoked)";
			if (indicatorToken == endToken) {
				hint = " (completed)";
			}
			append(indent + getClassName(command) , hint);
		}
		
		
		
		private static function updateIndentString():void {
			indent = "";
			if (indicatorToken == endToken || indicatorToken == markToken) {
				indent = indicatorToken;
			}
			var i:int = callDepth;
			while (i > 0) 
			{
				indent += indentToken; 
				i--;
			}
			if ( indicatorToken == beginToken) {
				indent += indicatorToken;
			}
		}
		
		private static function append(str:String,hint:String):void {
			var time:int = getTimer() - timeOffset;
			if (showHints) {
				str += hint;
			}
			if (showTimes) {
				if (timeOffset > 0) {
					str += "[" + time + "ms]";
				} else {
					str += "[" + formatTime(new Date()) + "]";
				}
			}
			if (showCaller) {
				str += " " + getCaller();
			}
			log(str);
		}
		
		private static function log(str:String):void {
			if (logToConsole) {
				trace(str);
			}
			logExternal(str);
		}
		
		private static function logToFile(str:String):void {
			if (fileStream == null) {
				var file:File = File.userDirectory.resolvePath(logDirectory);
				file.createDirectory();
				file = file.resolvePath(getLogFileName());
				fileStream = new FileStream();
				fileStream.openAsync(file,FileMode.WRITE); 
			}
			fileStream.writeUTFBytes(str + File.lineEnding);
		}
		
		
		
		
		private static function cleanLogs():void {
			var file:File = File.userDirectory.resolvePath(logDirectory);
			var files:Array = file.getDirectoryListing();
			if (files.length < maxLogsToKeep) {
				return;
			}
			files = files.sort(fileCompare);
			while (files.length > maxLogsToKeep) {
				(files.pop() as File).deleteFile();
			}
		}
		
		private static function fileCompare(f1:File,f2:File):int {
			if (f1 == null) {
				return 1;
			}
			if (f2 == null) {
				return 0;
			}
			if (f1.creationDate < f2.creationDate) {
				return -1;
			}
			if (f1.creationDate > f2.creationDate) {
				return 1;
			}
			return 0;
		}
		
		private static function getClassName(obj:Object):String {
			var name:String = getQualifiedClassName(obj);
			if (showPackageNames) {
				return name;
			}
			return removePackageName(name);
		}
		
		private static function removePackageName(str:String):String {
			var parts:Array = str.split(":");
			return parts[parts.length-1] as String;
		}
		
		private static function getLogFileName():String {
			var d:Date = new Date();
			dateFormatter.formatString = "YYYYMMDD_JJNNSS";
			return dateFormatter.format(d) + ".log";
		}
		
		private static function formatDate(d:Date):String {
			dateFormatter.formatString = "EEE MMM DD YYYY JJ:NN:SS.QQQ";
			return dateFormatter.format(d);
		}
		
		private static function formatTime(d:Date):String {
			dateFormatter.formatString = "JJ:NN:SS.QQQ";
			return dateFormatter.format(d);
		}
	}
}

