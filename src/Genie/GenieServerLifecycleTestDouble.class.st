Class {
	#name : 'GenieServerLifecycleTestDouble',
	#superclass : 'GenieServer',
	#instVars : [
		'startCount',
		'stopCount'
	],
	#category : 'Genie',
	#package : 'Genie'
}

{ #category : 'lifecycle' }
GenieServerLifecycleTestDouble >> start [

	startCount := self startCount + 1
]

{ #category : 'accessing' }
GenieServerLifecycleTestDouble >> startCount [

	^ startCount ifNil: [ 0 ]
]

{ #category : 'lifecycle' }
GenieServerLifecycleTestDouble >> stop [

	stopCount := self stopCount + 1
]

{ #category : 'accessing' }
GenieServerLifecycleTestDouble >> stopCount [

	^ stopCount ifNil: [ 0 ]
]
