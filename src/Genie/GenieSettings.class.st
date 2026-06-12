Class {
	#name : 'GenieSettings',
	#superclass : 'Object',
	#instVars : [
		'data'
	],
	#category : 'Genie',
	#package : 'Genie'
}

{ #category : 'instance creation' }
GenieSettings class >> defaultCopied [
	^ self new initializeDefaults
]

{ #category : 'accessing' }
GenieSettings >> asDictionary [
	^ data copy
]

{ #category : 'accessing' }
GenieSettings >> at: aKey [
	^ data at: aKey
]

{ #category : 'accessing' }
GenieSettings >> at: aKey ifAbsent: aBlock [
	^ data at: aKey ifAbsent: aBlock
]

{ #category : 'accessing' }
GenieSettings >> at: aKey put: aValue [
	^ data at: aKey put: aValue
]

{ #category : 'initialization' }
GenieSettings >> initializeDefaults [
	data := Dictionary new.
	data at: #stackSize put: 100.
	data at: #bindingInterface put: '127.0.0.1'.
	data at: #authToken put: ''.
	data at: #allowDangerousTools put: true.
	^ self
]

{ #category : 'accessing' }
GenieSettings >> stackSize [
	^ data at: #stackSize ifAbsent: [ 100 ]
]
