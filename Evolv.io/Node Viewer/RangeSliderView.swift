//
//  RangeSliderView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/13/25.
//

import SwiftUI
import ExpressionTree

struct RangeSliderView: View {
    let label: String
    @Binding var value: ClosedRange<ComponentType>
    let inBounds: ClosedRange<ComponentType>

	init(label: String,
		 value: Binding<ClosedRange<ComponentType>>,
		 in inBounds: ClosedRange<ComponentType> ) {
		self.label = label
		self._value = value
		self.inBounds = inBounds
	}

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .frame(width: 50)
            
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let totalRange = inBounds.upperBound - inBounds.lowerBound
                
                let lowerThumbPosition = (value.lowerBound - inBounds.lowerBound) / totalRange * ComponentType(trackWidth)
                let upperThumbPosition = (value.upperBound - inBounds.lowerBound) / totalRange * ComponentType(trackWidth)

                let lowerGesture = DragGesture()
                    .onChanged { gestureValue in
                        let newPosition = gestureValue.location.x
                        let newValue = ComponentType(newPosition / trackWidth) * totalRange + inBounds.lowerBound
                        // Clamp to prevent thumbs from crossing
                        self.value = min(newValue, value.upperBound)...value.upperBound
                    }
                
                let upperGesture = DragGesture()
                    .onChanged { gestureValue in
                        let newPosition = gestureValue.location.x
                        let newValue = ComponentType(newPosition / trackWidth) * totalRange + inBounds.lowerBound
                        // Clamp to prevent thumbs from crossing
                        self.value = value.lowerBound...max(newValue, value.lowerBound)
                    }

                ZStack(alignment: .leading) {
                    // Track
                    Capsule().fill(Color.secondary.opacity(0.2))
                    
                    // Selected Range
                    Capsule().fill(Color.accentColor)
                        .frame(width: CGFloat(upperThumbPosition - lowerThumbPosition))
                        .offset(x: CGFloat(lowerThumbPosition))
                    
                    // Thumbs
                    Circle().fill(Color.white).shadow(radius: 2)
                        .frame(width: 20, height: 20)
                        .offset(x: CGFloat(lowerThumbPosition - 10))
                        .gesture(lowerGesture)
                    
                    Circle().fill(Color.white).shadow(radius: 2)
                        .frame(width: 20, height: 20)
                        .offset(x: CGFloat(upperThumbPosition - 10))
                        .gesture(upperGesture)
                }
            }
            .frame(height: 20)
            
            VStack {
                Text(String(format: "%.2f", value.lowerBound))
                Text(String(format: "%.2f", value.upperBound))
            }
            .font(.caption.monospaced())
            .frame(width: 50)
        }
    }
}
