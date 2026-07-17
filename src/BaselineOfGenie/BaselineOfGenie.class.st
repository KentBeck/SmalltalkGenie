Class {
	#name : 'BaselineOfGenie',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfGenie',
	#package : 'BaselineOfGenie'
}

{ #category : 'baselines' }
BaselineOfGenie >> baseline: spec [
	<baseline>
	spec for: #common do: [
		spec
			baseline: 'Teapot' with: [ spec repository: 'github://zeroflag/Teapot:master/source' ];
			baseline: 'NeoJSON' with: [ spec repository: 'github://svenvc/NeoJSON:master/repository' ].
		spec package: 'Genie' with: [ spec requires: #('Teapot' 'NeoJSON') ].
		spec package: 'Genie-MemoryLoad' ]
]
