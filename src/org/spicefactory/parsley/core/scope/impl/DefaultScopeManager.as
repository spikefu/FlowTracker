/*
 * Copyright 2009 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.spicefactory.parsley.core.scope.impl {
import com.yellowbadger.util.FlowTracker;

import flash.system.ApplicationDomain;
import flash.utils.Dictionary;

import org.spicefactory.lib.errors.IllegalArgumentError;
import org.spicefactory.parsley.core.context.Context;
import org.spicefactory.parsley.core.scope.Scope;
import org.spicefactory.parsley.core.scope.ScopeManager;

/**
 * Default implementation of the ScopeManager interface.
 * 
 * @author Jens Halm
 */
public class DefaultScopeManager implements ScopeManager {
	
	
	private var scopes:Dictionary = new Dictionary();
	private var domain:ApplicationDomain;
	
	
	/**
	 * Creates a new instance.
	 * 
	 * @param scopes the scopes this instance should manage
	 */
	function DefaultScopeManager (context:Context, scopeDefs:Array, domain:ApplicationDomain) {
		for each (var scopeDef:ScopeDefinition in scopeDefs) {
			scopes[scopeDef.name] = new DefaultScope(context, scopeDef, domain);
		}
		this.domain = domain;
	}
	
	
	/**
	 * @inheritDoc
	 */
	public function hasScope (name:String) : Boolean {
		return (scopes[name] != undefined);
	}
	
	/**
	 * @inheritDoc
	 */
	public function getScope (name:String) : Scope {
		if (!hasScope(name)) {
			throw new IllegalArgumentError("This router does not contain a scope with name " + name);
		}
		return scopes[name] as Scope;
	}
	
	/**
	 * @inheritDoc
	 */
	public function getAllScopes () : Array {
		var scopes:Array = new Array();
		for each (var scope:Scope in this.scopes) {
			scopes.push(scope);
		}
		return scopes;
	}
	
	/**
	 * @inheritDoc
	 */
	public function dispatchMessage (message:Object, selector:* = undefined) : void {
		if (FlowTracker.on) {
			FlowTracker.begin(message);
		}
		for each (var sc:Scope in scopes) {
			sc.dispatchMessage(message, selector);
		}
		if (FlowTracker.on) {
			FlowTracker.end(message);
		}
	}
	
	
}
}
