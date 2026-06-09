Class {
	#name : #Wish,
	#superclass : #Object,
	#instVars : [
		'arguments'
	],
	#category : #Genie
}

{ #category : #accessing }
Wish >> at: aKey [
	^ arguments at: aKey asString
]

{ #category : #accessing }
Wish >> at: aKey ifAbsent: aBlock [
	^ arguments at: aKey asString ifAbsent: aBlock
]

{ #category : #accessing }
Wish >> contents [
	^ String streamContents: [ :stream | (NeoJSONWriter on: stream) nextPut: arguments ]
]

{ #category : #accessing }
Wish >> entity [
	^ self
]

{ #category : #accessing }
Wish >> setArguments: aDictionary [
	arguments := aDictionary.
	^ self
]
