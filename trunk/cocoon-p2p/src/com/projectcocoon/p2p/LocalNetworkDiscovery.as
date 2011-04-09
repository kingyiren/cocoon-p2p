/*
* Copyright 2011 (c) Peter Elst, project-cocoon.com.
*
* Permission is hereby granted, free of charge, to any person
* obtaining a copy of this software and associated documentation
* files (the "Software"), to deal in the Software without
* restriction, including without limitation the rights to use,
* copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following
* conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
* OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
* NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
* HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
* OTHER DEALINGS IN THE SOFTWARE.
*/
package com.projectcocoon.p2p
{
	
	import com.projectcocoon.p2p.events.ClientEvent;
	import com.projectcocoon.p2p.events.MessageEvent;
	import com.projectcocoon.p2p.vo.ClientVO;
	import com.projectcocoon.p2p.vo.MessageVO;
	
	import flash.events.EventDispatcher;
	import flash.events.NetStatusEvent;
	import flash.net.GroupSpecifier;
	import flash.net.NetConnection;
	import flash.net.NetGroup;
	
	import mx.collections.ArrayCollection;

	[Event(name="clientAdded", type="com.projectcocoon.p2p.events.ClientEvent")]
	[Event(name="clientUpdate", type="com.projectcocoon.p2p.events.ClientEvent")]
	[Event(name="clientRemoved", type="com.projectcocoon.p2p.events.ClientEvent")]
	[Event(name="dataReceived", type="com.projectcocoon.p2p.events.MessageEvent")]
	public class LocalNetworkDiscovery extends EventDispatcher
	{
	
		[Bindable] public var clientsConnected:uint = 0;
		[Bindable] public var clients:ArrayCollection = new ArrayCollection();

		private var _nc:NetConnection;
		private var _groupSpec:GroupSpecifier;
		private var _group:NetGroup;
		private var _clientName:String;
		private var _localClient:ClientVO;
		private var _groupName:String = "default";
		private var _multicastAddress:String = "225.225.0.1:30303";
		private var _receiveLocal:Boolean = false;
		private var _activeTransfer:Boolean = false;
		
		public function LocalNetworkDiscovery()
		{
			connect();
		}
		
		public function connect():void
		{
			_nc = new NetConnection();
			_nc.addEventListener(NetStatusEvent.NET_STATUS, onNetStatus);
			_nc.connect("rtmfp:");
		}
		
		private function onNetStatus(evt:NetStatusEvent):void
		{
			switch (evt.info.code) {
				case NetStatusCode.NETCONNECTION_CONNECT_SUCCESS:
					setupGroup();
				break;
				case NetStatusCode.NETGROUP_CONNECT_SUCCESS:
					setupClient();
				break;
				case NetStatusCode.NETGROUP_NEIGHBOUR_CONNECT:
					onClientConnect(evt);
				break;
				case NetStatusCode.NETGROUP_NEIGHBOUR_DISCONNECT:
					onClientDisconnect(evt);			
				break;
				case NetStatusCode.NETGROUP_POSTING_NOTIFY:
					onNetGroupPosting(evt);
				break;
				case NetStatusCode.NETGROUP_SENDTO_NOTIFY:
					onNetGroupSendTo(evt);
				break;
			}
		}
		
		private function setupGroup():void
		{
			_groupSpec = new GroupSpecifier(groupName);
			_groupSpec.postingEnabled = true;
			_groupSpec.routingEnabled = true;
			_groupSpec.ipMulticastMemberUpdatesEnabled = true;
			_groupSpec.objectReplicationEnabled = true;
			_groupSpec.addIPMulticastAddress(multicastAddress);
			
			_group = new NetGroup(_nc, _groupSpec.groupspecWithAuthorizations());
			_group.addEventListener(NetStatusEvent.NET_STATUS, onNetStatus);
		}
		
		private function setupClient():void
		{			
			_localClient = new ClientVO(getClientName(), _nc.nearID, _group.convertPeerIDToGroupAddress(_nc.nearID));
			
			clientsConnected = _group.estimatedMemberCount;
			clients.addItem(_localClient);
		}
		
		private function onClientConnect(evt:NetStatusEvent):void
		{
			clientsConnected = _group.estimatedMemberCount;
			
			var client:ClientVO = new ClientVO("", evt.info.peerID, _group.convertPeerIDToGroupAddress(evt.info.peerID));
			
			clients.addItem(client);
			announceName();
		}
		
		private function onNetGroupPosting(evt:NetStatusEvent):void
		{
			var msg:MessageVO = new MessageVO(new ClientVO(evt.info.message.client.clientName, evt.info.message.client.peerID, evt.info.message.client.groupID), evt.info.message.data, evt.info.message.destination, evt.info.message.type, evt.info.message.scope, evt.info.message.command);
			if(msg.type == CommandType.SERVICE) {
				if(msg.command == CommandList.ANNOUNCE_NAME) {
					for(var j:uint=0; j<clients.length; j++) {
						var client:ClientVO = ClientVO(clients[j]);
						if(client.groupID == msg.client.groupID) {
							client.clientName = evt.info.message.client.clientName;
							dispatchEvent(new ClientEvent(ClientEvent.CLIENT_UPDATE, client));
							break;
						}
					}
				}
			} else {
				dispatchEvent(new MessageEvent(MessageEvent.DATA_RECEIVED, new MessageVO(new ClientVO(evt.info.message.client.clientName, evt.info.message.client.peerID, evt.info.message.client.groupID), evt.info.message.data, evt.info.message.destination, evt.info.message.type, evt.info.message.scope)));
			}
		}
		
		private function onNetGroupSendTo(evt:NetStatusEvent):void
		{
			if(evt.info.fromLocal == true) {
				dispatchEvent(new MessageEvent(MessageEvent.DATA_RECEIVED, new MessageVO(new ClientVO(evt.info.message.client.clientName, evt.info.message.client.peerID, evt.info.message.client.groupID), evt.info.message.data, evt.info.message.destination, evt.info.message.type, evt.info.message.scope)));
			} else {
				_group.sendToNearest(evt.info.message, evt.info.message.destination);
			}
		}
		
		private function onClientDisconnect(evt:NetStatusEvent):void
		{
			clientsConnected = _group.estimatedMemberCount;
			for(var i:uint=0; i<clients.length; i++) {
				var client:ClientVO = ClientVO(clients[i]);
				if(client.groupID == _group.convertPeerIDToGroupAddress(evt.info.peerID)) {
					dispatchEvent(new ClientEvent(ClientEvent.CLIENT_REMOVED, client));
					clients.removeItemAt(i);
					return;
				}
			}
		}
		
		private function getClientName():String
		{
			if(!_clientName) _clientName = _group.convertPeerIDToGroupAddress(_nc.nearID);
			return _clientName;
		}
		
		private function announceName():void
		{
			_group.post(new MessageVO(_localClient, null, null, CommandType.SERVICE, CommandScope.ALL, CommandList.ANNOUNCE_NAME));
		}
		
		public function sendMessageToClient(value:String, groupID:String):void
		{
			var msg:MessageVO = new MessageVO(_localClient, value, groupID, CommandType.MESSAGE, CommandScope.DIRECT);
			
			if(loopback && (groupID != _localClient.groupID)) dispatchEvent(new MessageEvent(MessageEvent.DATA_RECEIVED, msg));
			_group.sendToNearest(msg, groupID);
		}
		
		public function sendMessageToAll(value:String):void
		{
			var msg:MessageVO = new MessageVO(_localClient, value, null, CommandType.MESSAGE, CommandScope.ALL);
			if(loopback) dispatchEvent(new MessageEvent(MessageEvent.DATA_RECEIVED, msg));
			_group.post(msg);
		}
		
		public function get clientName():String
		{
			return _clientName;
		}
		public function set clientName(val:String):void
		{
			_clientName = val;
			if(_localClient) {
				_localClient.clientName = val;
				announceName();
			}
		}		
		
		public function get groupName():String
		{
			return _groupName;
		}
		public function set groupName(val:String):void
		{
			_groupName = val;
		}
		
		public function get multicastAddress():String
		{
			return _multicastAddress;
		}
		public function set multicastAddress(val:String):void
		{
			_multicastAddress = val;
		}
		
		public function get loopback():Boolean
		{
			return _receiveLocal;
		}
		public function set loopback(bool:Boolean):void
		{
			_receiveLocal = bool;
		}		
		
	}
	
}