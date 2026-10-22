import SwiftUI
import UIKit

// Photo-matched to all six M-VAVE product galleries; see docs/panel-finishes.md.
// Stable raw names preserve the existing saved finish selection.
enum PanelFinish: String, CaseIterable, Identifiable {
    case black = "Black", purple = "Purple", orange = "Orange", blackGreen = "Black-Green", coolGray = "Cool Gray", whiteBlue = "White-Blue"
    var id: String { rawValue }
    var palette: PanelPalette {
        switch self {
        case .black: return PanelPalette(body:0x3b3c3c, bodyBottom:0x343535, accent:0x555757, control:0x303231, controlBottom:0x272928, ink:0xe5e6e3, keybed:0x303231, keybedBottom:0x292b2a, controlInk:0xf0f1eb, led:0xbaffad, ledOff:0x18251c, pressed:0x54776a, pressedBottom:0x2d5145, pressedInk:0xf0fff6)
        case .purple: return PanelPalette(body:0xb88fc9, bodyBottom:0xae82bf, accent:0x9a79ae, control:0x8178b7, controlBottom:0x7b72af, ink:0x211728, keybed:0x7b72af, keybedBottom:0x736aa6, controlInk:0x06060c, led:0xe9caff, ledOff:0x251e33, pressed:0x5d4d89, pressedBottom:0x463665, pressedInk:0xfff7ff)
        case .orange: return PanelPalette(body:0xbf704c, bodyBottom:0xb36746, accent:0xa75f43, control:0xa06959, controlBottom:0x915c4f, ink:0x0c0806, keybed:0x996353, keybedBottom:0x8f5b4c, controlInk:0xffffff, led:0xffd59c, ledOff:0x322219, pressed:0x7b432d, pressedBottom:0x5e3323, pressedInk:0xfff6e6)
        case .blackGreen: return PanelPalette(body:0x3b3c3c, bodyBottom:0x343535, accent:0x555757, control:0x7ccdc4, controlBottom:0x69bbb2, ink:0xe5e6e3, keybed:0x74c8bf, keybedBottom:0x6bbeb5, controlInk:0x203d3c, led:0xa6fff0, ledOff:0x112b2a, pressed:0x376d6c, pressedBottom:0x245250, pressedInk:0xf0fffd)
        case .coolGray: return PanelPalette(body:0xdfd8d0, bodyBottom:0xd5cdc3, accent:0xc6beb5, control:0x444c4e, controlBottom:0x363e40, ink:0x252a2b, keybed:0x3c4446, keybedBottom:0x343c3e, controlInk:0xeef4f2, led:0xe2edff, ledOff:0x1b2931, pressed:0x325c6b, pressedBottom:0x234550, pressedInk:0xf1fcff)
        case .whiteBlue: return PanelPalette(body:0xeeece4, bodyBottom:0xe3e0d7, accent:0xd2d0c8, control:0x52758e, controlBottom:0x42637c, ink:0x2a343a, keybed:0x4a6c85, keybedBottom:0x42637b, controlInk:0xfffbf5, led:0xa7ddff, ledOff:0x182638, pressed:0x365371, pressedBottom:0x263c55, pressedInk:0xfffbf1)
        }
    }
    var swatch: Color { Color(uiColor:UIColor(rgb:palette.body)) }
    var secondarySwatch: Color { Color(uiColor:UIColor(rgb:palette.control)) }
    /// Bright finish-specific accent remains readable on the dark transport/gutter.
    var accentColor: Color { Color(uiColor:UIColor(rgb:palette.led)) }
    /// The dark Black panel keeps its original optical treatment. Colored key
    /// faces need shallower, narrower seats and a more localized emission.
    var lampStyle:PanelLampStyle {
        switch self {
        case .black:
            return PanelLampStyle(core:palette.lampCore,halo:palette.led,recess:palette.ledOff,haloAlpha:0.68,haloBlur:7,recessInset:2,recessRadius:4)
        case .purple:
            return PanelLampStyle(core:0xfff1fc,halo:0xe7a3e7,recess:0x473962,haloAlpha:0.46,haloBlur:4.5,recessInset:0.75,recessRadius:2.75)
        case .orange:
            return PanelLampStyle(core:0xfff0d8,halo:0xffbf72,recess:0x4c3026,haloAlpha:0.40,haloBlur:4.5,recessInset:0.75,recessRadius:2.75)
        case .blackGreen:
            return PanelLampStyle(core:0xe7fff4,halo:0xb8ffe8,recess:0x244c48,haloAlpha:0.38,haloBlur:4.5,recessInset:0.75,recessRadius:2.75)
        case .coolGray:
            return PanelLampStyle(core:0xeaf4ff,halo:0xb8d8f4,recess:0x293a46,haloAlpha:0.42,haloBlur:5,recessInset:1,recessRadius:3)
        case .whiteBlue:
            return PanelLampStyle(core:0xe8f6ff,halo:0x9edcff,recess:0x294052,haloAlpha:0.42,haloBlur:4.5,recessInset:0.75,recessRadius:2.75)
        }
    }
}
struct PanelLampStyle:Equatable {
    let core:UInt32,halo:UInt32,recess:UInt32
    let haloAlpha:CGFloat,haloBlur:CGFloat,recessInset:CGFloat,recessRadius:CGFloat
}
struct PanelPalette {
    let body:UInt32, bodyBottom:UInt32, accent:UInt32, control:UInt32, controlBottom:UInt32, ink:UInt32
    let keybed:UInt32, keybedBottom:UInt32, controlInk:UInt32
    let led:UInt32, ledOff:UInt32, pressed:UInt32, pressedBottom:UInt32, pressedInk:UInt32
    static func contrast(_ a:UInt32,_ b:UInt32)->Double {
        func luminance(_ rgb:UInt32)->Double {
            let weights=[0.2126,0.7152,0.0722]
            return zip([16,8,0],weights).reduce(0) { result, component in
                let value=Double((rgb >> component.0)&255)/255
                return result + (value<=0.04045 ? value/12.92 : pow((value+0.055)/1.055,2.4))*component.1
            }
        }
        let x=luminance(a),y=luminance(b)
        return (max(x,y)+0.05)/(min(x,y)+0.05)
    }
    /// A quiet outline separates adjacent keys without changing the product finish.
    var keyOutline:UInt32 {
        var result:UInt32=0
        for shift in [16,8,0] {
            let base=Double((controlBottom >> shift)&255),ink=Double((controlInk >> shift)&255)
            result |= UInt32((base*0.74+ink*0.26).rounded()) << shift
        }
        return result
    }
    /// Physical scan duty normalization; never derived from touch/held state.
    static func firmwareOpacity(_ duty:Float)->Float {
        guard duty.isFinite else{return 0}
        return max(0,min(1,duty*(1100.0/95.0)))
    }
    /// Display response only: lift low nonzero duty on a small screen without
    /// inventing an on state at zero, a minimum-brightness step, or new timing.
    /// A dim lamp is a generic firmware-controlled indicator, not a scale/root label.
    static func lampOpacity(_ duty:Float)->Float {
        let level=firmwareOpacity(duty)
        return level*1.03/(level+0.03)
    }
    /// A near-white emitter with a small amount of the selected finish's tint.
    var lampCore:UInt32 {
        var result:UInt32=0
        for shift in [16,8,0] {
            result |= UInt32((255*0.90+Double((led >> shift)&255)*0.10).rounded()) << shift
        }
        return result
    }
}
private extension UIColor {
    convenience init(rgb:UInt32, alpha:CGFloat=1) {self.init(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)}
}
struct PanelView: UIViewRepresentable {
    let instrument: Instrument
    @ObservedObject private var frames:InstrumentDisplayState
    init(instrument:Instrument,finish:PanelFinish = .black,knobReferenceHeight:CGFloat? = nil,showScreen:@escaping ()->Void) {
        self.instrument=instrument;self.frames=instrument.displayState
        self.finish=finish;self.knobReferenceHeight=knobReferenceHeight;self.showScreen=showScreen
    }
    var finish: PanelFinish = .black
    var knobReferenceHeight:CGFloat?
    var showScreen: () -> Void
    func makeUIView(context: Context) -> HardwarePanel {
        let view=HardwarePanel();view.instrument=instrument;view.finish=finish;view.knobReferenceHeight=knobReferenceHeight;view.showScreen=showScreen;return view
    }
    func updateUIView(_ view: HardwarePanel, context: Context) {view.instrument=instrument;view.finish=finish;view.knobReferenceHeight=knobReferenceHeight;view.showScreen=showScreen;view.refreshDisplay()}
}
/// A layout transition changes UIKit's local coordinates under a held knob.
/// Re-anchor its next move without converting that coordinate shift to detents.
struct PanelKnobDragAnchor {
    private var needsReset=false
    mutating func geometryChanged(){needsReset=true}
    mutating func update(anchorY:CGFloat,currentY:CGFloat)->(steps:Int,anchorY:CGFloat) {
        if needsReset {needsReset=false;return (0,currentY)}
        return KnobDrag.update(anchorY:anchorY,currentY:currentY)
    }
}
private struct PanelControl {
    enum Kind {case key(Int), encoder(Int), master, screen}
    let name:String, rect:CGRect, kind:Kind
}
private final class AccessibleControl:UIAccessibilityElement {
    var activate:(() -> Void)?
    var adjust:((Int) -> Void)?
    var describeValue:(() -> String)?
    override var accessibilityValue:String? {get{describeValue?()}set{}}
    override func accessibilityActivate()->Bool {activate?();return true}
    override func accessibilityIncrement(){adjust?(1)}
    override func accessibilityDecrement(){adjust?(-1)}
}
final class HardwarePanel:UIView {
    weak var instrument:Instrument?
    var haptics=ControlHaptics.shared
    var finish:PanelFinish = .black {
        didSet {if oldValue != finish {artworkKey=nil;refreshDisplay()}}
    }
    // Same compact-panel height in both toolbar states; only window resizing
    // changes the knob diameter. Never infer it from a previous rendered frame.
    var knobReferenceHeight:CGFloat? {
        didSet {if oldValue != knobReferenceHeight {artworkKey=nil;setNeedsLayout()}}
    }
    var showScreen:(() -> Void)?
    private var controls:[PanelControl]=[]
    private var touches:[ObjectIdentifier:(Int,CGPoint)]=[:]
    private var knobDragAnchors:[ObjectIdentifier:PanelKnobDragAnchor]=[:]
    private var previousLayoutBounds:CGRect?
    private var layoutDeferred=true
    private var held:Set<Int>=[]
    private var angles:[Int:CGFloat]=[:]
    private struct TouchReceipt {
        var began=0, ended=0, cancelled=0, downs=0, ups=0, peakTouches=0
        var maxBeganDelay:Double=0
    }
    // Transient, opt-in UI-test observability: actual UIKit events, never persisted.
    private let touchDiagnostics=ProcessInfo.processInfo.arguments.contains("--panel-touch-diagnostics")
    private var receipts:[Int:TouchReceipt]=[:]
    private var keyboardRect=CGRect.zero
    private struct ArtworkKey:Equatable {let bounds:CGRect, scale:CGFloat, finish:PanelFinish}
    private var artworkKey:ArtworkKey?
    private var artwork:CGImage?
    private var pressedArtwork:[Int:CGImage]=[:]
    private var indicatorArtwork:[Int:CGImage]=[:]
    private let artworkLayer=CALayer(),screenLayer=CALayer()
    private var pressedLayers:[Int:CALayer]=[:],indicatorLayers:[Int:CALayer]=[:],lampLayers:[Int:CALayer]=[:]
    private var lastScreen:CGImage?
    // Internal, transient counters make cache behavior testable without timing assertions.
    private(set) var artworkBuildCount=0
    private(set) var artworkPixelSize=CGSize.zero

    private let labels=["FX","SEL","ENV","LFO","EDIT","GLO","HOME","SAVE","ARP","SEQ","PLAY\nSTOP","REC"]
    private let whites=[0,2,4,6,7,9,11,12,14,16,18,19,21,23,24,26]
    private let blacks=[(1,0),(3,1),(5,2),(8,4),(10,5),(13,7),(15,8),(17,9),(20,11),(22,12),(25,14)]
    override init(frame:CGRect) {
        super.init(frame:frame);isOpaque=false;backgroundColor = .clear;isMultipleTouchEnabled=true
        accessibilityIdentifier="Instrument panel";isAccessibilityElement=false
        artworkLayer.name="Panel artwork";screenLayer.name="Firmware LCD"
        layer.addSublayer(artworkLayer);layer.addSublayer(screenLayer)
        screenLayer.minificationFilter = .nearest;screenLayer.magnificationFilter = .nearest
    }
    required init?(coder:NSCoder){fatalError()}
    private func note(_ n:Int)->String {let midi=n+53;return ["C","C sharp","D","D sharp","E","F","F sharp","G","G sharp","A","A sharp","B"][midi%12]+"\(midi/12-1)"}
    override func layoutSubviews() {
        super.layoutSubviews()
        let w=bounds.width, h=bounds.height
        let keyboardHeight=min(240,max(118,h*0.42)), upper=h-keyboardHeight-8
        // SwiftUI may pass a tiny intermediate frame during a size transition.
        // Wait until even the nested knob faces have positive raster dimensions.
        guard w.isFinite,h.isFinite,w>=320,upper>=128 else {
            layoutDeferred=true;artworkKey=nil;accessibilityElementsHidden=true
            CATransaction.begin();CATransaction.setDisableActions(true)
            layer.sublayers?.forEach{$0.isHidden=true}
            CATransaction.commit()
            for key in Array(knobDragAnchors.keys) {knobDragAnchors[key]?.geometryChanged()}
            return
        }
        layoutDeferred=false;accessibilityElementsHidden=false
        artworkLayer.isHidden=false;screenLayer.isHidden=false
        if previousLayoutBounds != bounds {
            artworkKey=nil
            if previousLayoutBounds != nil {
                for key in Array(knobDragAnchors.keys) {knobDragAnchors[key]?.geometryChanged()}
            }
        }
        previousLayoutBounds=bounds
        // Lay out directly in screen points: the phone's wide canvas is an instrument,
        // rather than a small scale model centered inside a fixed hardware aspect ratio.
        let left=w*0.235
        let leftSlot=(left-22)/2
        // Compute all eight knobs from the compact panel, even when the toolbar
        // is hidden. A larger LCD must not feed back into the knob diameter.
        let requestedHeight=knobReferenceHeight ?? h
        let referenceH=requestedHeight.isFinite ? min(h,max(0,requestedHeight)) : h
        let candidateUpper=referenceH-min(240,max(118,referenceH*0.42))-8
        // SwiftUI can publish a tiny intermediate reference before UIKit bounds
        // catch up. Use the valid current geometry rather than a negative knob.
        let referenceUpper=candidateUpper>=128 ? candidateUpper : upper
        let referenceColumnLimit=max(w*0.23,w-left-24-(6*44+5*5))
        let referenceScreen=min(w*0.29,max(w*0.23,referenceUpper-4),referenceColumnLimit)
        let referenceRight=w-left-referenceScreen-24
        let knob=min(90,min(leftSlot,min((referenceUpper-88)/2,min((referenceRight-30)/4,referenceUpper*0.36))))
        // Give height recovered from the toolbar to the LCD. Retain room for
        // six44pt function keys and four fixed-size knobs on its right.
        let screenColumnLimit=max(0,w-left-24-max(6*44+5*5,4*knob+30))
        let screenWidth=min(max(w*0.23,upper-4),screenColumnLimit)
        let rightX=left+screenWidth+12, rightWidth=w-rightX-12
        // One rigid, centered2×2 block. Use the compact panel to choose a
        // shared horizontal/vertical gap, then translate the block as a whole.
        let clusterGap=max(0,min(leftSlot+4-knob,referenceUpper-63-2*knob))
        let clusterSize=2*knob+clusterGap
        let firstKnobX=(left-clusterSize)/2
        let secondKnobX=firstKnobX+knob+clusterGap
        let firstY=(19+upper-44-clusterSize)/2
        let secondY=firstY+knob+clusterGap
        let referenceFunctionTop=max(knob+26,referenceUpper*0.51), gap:CGFloat=5
        let lowerAnchorOffset=upper-referenceUpper
        // The entire right control group keeps its compact geometry and follows
        // the bottom of the upper panel, above the keyboard.
        let functionTop=referenceFunctionTop+lowerAnchorOffset
        // Center the visible label+knob row above the compact function grid.
        // Its15pt label sits above the face; preserve the same lower anchor.
        let rightKnobY=(referenceFunctionTop-knob+15)/2+lowerAnchorOffset
        let screenSize=min(screenWidth-8,upper-16)
        controls=[
            PanelControl(name:"MASTER",rect:CGRect(x:firstKnobX,y:firstY,width:knob,height:knob),kind:.master),
            PanelControl(name:"SELECT",rect:CGRect(x:secondKnobX,y:firstY,width:knob,height:knob),kind:.encoder(0)),
            PanelControl(name:"PRESETS",rect:CGRect(x:firstKnobX,y:secondY,width:knob,height:knob),kind:.encoder(6)),
            PanelControl(name:"ALGORITHM",rect:CGRect(x:secondKnobX,y:secondY,width:knob,height:knob),kind:.encoder(1)),
            PanelControl(name:"OCT−",rect:CGRect(x:9,y:upper-39,width:(left-22)/2,height:36),kind:.key(0)),
            PanelControl(name:"OCT+",rect:CGRect(x:13+(left-22)/2,y:upper-39,width:(left-22)/2,height:36),kind:.key(1)),
            PanelControl(name:"Enlarge display",rect:CGRect(x:left+4+(screenWidth-8-screenSize)/2,y:12,width:screenSize,height:screenSize),kind:.screen)
        ]
        let rightKnob=knob
        for i in 0..<4 {
            let slot=rightWidth/4
            controls.append(PanelControl(name:"KNOB\(i+1)",rect:CGRect(x:rightX+slot*CGFloat(i)+(slot-rightKnob)/2,y:rightKnobY,width:rightKnob,height:rightKnob),kind:.encoder(i+2)))
        }
        let buttonWidth=(rightWidth-gap*5)/6, buttonHeight=(referenceUpper-referenceFunctionTop-gap-3)/2
        for i in 0..<12 {controls.append(PanelControl(name:labels[i].replacingOccurrences(of:"\n",with:" "),rect:CGRect(x:rightX+CGFloat(i%6)*(buttonWidth+gap),y:functionTop+CGFloat(i/6)*(buttonHeight+gap),width:buttonWidth,height:buttonHeight),kind:.key(i+2)))}
        keyboardRect=CGRect(x:3,y:upper+5,width:w-6,height:keyboardHeight+1)
        let pitch=(w-16)/16, keyWidth=pitch-2
        for (i,n) in whites.enumerated() {controls.append(PanelControl(name:note(n),rect:CGRect(x:8+CGFloat(i)*pitch,y:upper+8+keyboardHeight*0.48,width:keyWidth,height:keyboardHeight*0.52-4),kind:.key(n+14)))}
        for (n,after) in blacks {controls.append(PanelControl(name:note(n),rect:CGRect(x:8+pitch*0.5+CGFloat(after)*pitch,y:upper+10,width:keyWidth,height:keyboardHeight*0.43),kind:.key(n+14)))}
        accessibilityElements=controls.enumerated().map {i,c in
            let a=AccessibleControl(accessibilityContainer:self)
            a.accessibilityLabel=c.name;a.accessibilityIdentifier=c.name;a.accessibilityFrameInContainerSpace=c.rect
            if case .key(let id)=c.kind {
                a.describeValue={ [weak self] in
                    guard let self else{return "Released"}
                    let down=self.held.contains(id)
                    if self.touchDiagnostics {
                        let r=self.receipts[id] ?? TouchReceipt()
                        return "held=\(down ? 1 : 0);began=\(r.began);ended=\(r.ended);cancelled=\(r.cancelled);downs=\(r.downs);ups=\(r.ups);peakTouches=\(r.peakTouches);maxBeganDelayMs=\(Int(r.maxBeganDelay*1000))"
                    }
                    return down ? "Pressed" : "Released"
                }
            }
            switch c.kind {
            case .master,.encoder:a.accessibilityTraits=[.adjustable];a.accessibilityHint="Swipe up or down to turn";a.adjust={ [weak self] n in self?.turn(i,n) }
            default:a.accessibilityTraits=[.button];a.activate={ [weak self] in
                guard let self else{return}
                if case .screen=c.kind {self.showScreen?();self.haptics.button();return}
                self.press(i,true);DispatchQueue.main.asyncAfter(deadline:.now()+0.15){self.press(i,false)}
            }
            }
            return a
        }
        refreshDisplay()
    }
    private func box(_ rect:CGRect,_ radius:CGFloat,_ top:UInt32,_ bottom:UInt32,_ stroke:UInt32?=nil) {
        let ctx=UIGraphicsGetCurrentContext()!, path=UIBezierPath(roundedRect:rect,cornerRadius:radius)
        ctx.saveGState();path.addClip()
        let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[UIColor(rgb:top).cgColor,UIColor(rgb:bottom).cgColor] as CFArray,locations:[0,1])!
        ctx.drawLinearGradient(gradient,start:CGPoint(x:rect.midX,y:rect.minY),end:CGPoint(x:rect.midX,y:rect.maxY),options:[]);ctx.restoreGState()
        if let stroke {UIColor(rgb:stroke).setStroke();path.lineWidth=1;path.stroke()}
    }
    private func text(_ value:String,_ rect:CGRect,_ size:CGFloat=10,_ tint:UInt32=0xe1e5e3,_ weight:UIFont.Weight = .medium) {
        let style=NSMutableParagraphStyle();style.alignment = .center
        (value as NSString).draw(in:rect,withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:weight),.foregroundColor:UIColor(rgb:tint),.paragraphStyle:style])
    }
    private func lampRect(_ c:PanelControl,_ id:Int)->CGRect {
        id>=14 ? CGRect(x:c.rect.midX-2,y:c.rect.minY+10,width:4,height:max(16,c.rect.height*0.4))
               : CGRect(x:c.rect.midX-7,y:c.rect.minY+3,width:14,height:2)
    }
    private func keyFace(_ c:PanelControl,_ id:Int,_ down:Bool,_ p:PanelPalette) {
        let ink=p.controlInk
        box(c.rect,id>=14 ? 9 : 7,p.control,p.controlBottom,p.controlBottom)
        if id>=14 {
            // Keep this stroke inside the sprite so held and released edges match.
            let edge=UIBezierPath(roundedRect:c.rect.insetBy(dx:0.65,dy:0.65),cornerRadius:8.35)
            UIColor(rgb:p.keyOutline).setStroke();edge.lineWidth=1.3;edge.stroke()
            if let k=blacks.firstIndex(where:{$0.0==id-14}),k<10,c.rect.height>45 {
                text(["OP1","OP2","OP3","OP4","OP5","OP6","PIT","GLO","MONO","POLY"][k],CGRect(x:c.rect.minX,y:c.rect.maxY-16,width:c.rect.width,height:12),9,ink)
            }
        } else {
            let title=id<2 ? c.name : labels[id-2]
            text(title,CGRect(x:c.rect.minX+1,y:c.rect.midY-(title.contains("\n") ? 12 : 6),width:c.rect.width-2,height:28),id<2 ? 12 : 11,ink,.semibold)
        }
        // Optical seats vary with the finish; the emitter and key targets keep
        // their original bounds. Black retains the exact build18 seat.
        let lamp=finish.lampStyle
        UIColor(rgb:lamp.recess).setFill();UIBezierPath(roundedRect:lampRect(c,id).insetBy(dx:-lamp.recessInset,dy:-lamp.recessInset),cornerRadius:lamp.recessRadius).fill()
        if down {
            // Immediate inset feedback has no luminous edge or whole-face hue flip.
            // This is baked into the held sprite, independently of firmware lamps.
            let ctx=UIGraphicsGetCurrentContext()!
            ctx.saveGState()
            UIBezierPath(roundedRect:c.rect.insetBy(dx:2,dy:2),cornerRadius:id>=14 ? 7 : 5).addClip()
            UIColor(white:0,alpha:0.22).setStroke()
            let inset=UIBezierPath(roundedRect:c.rect.insetBy(dx:2,dy:1),cornerRadius:id>=14 ? 7 : 5)
            inset.lineWidth=3;inset.stroke()
            ctx.restoreGState()
        }
    }
    private let lampPadding:CGFloat=12
    private func lampSprite(_ size:CGSize,_ scale:CGFloat,_ p:PanelPalette)->CGImage {
        let lamp=finish.lampStyle
        return raster(size,scale) {
            let emitter=CGRect(origin:.zero,size:size).insetBy(dx:lampPadding,dy:lampPadding)
            let path=UIBezierPath(roundedRect:emitter,cornerRadius:2)
            let ctx=UIGraphicsGetCurrentContext()!
            ctx.saveGState()
            // Rasterize the localized halo once. Live frames only composite opacity;
            // no CALayer shadow blur, filter, or offscreen shadow pass is needed.
            ctx.setShadow(offset:.zero,blur:lamp.haloBlur,color:UIColor(rgb:lamp.halo,alpha:lamp.haloAlpha).cgColor)
            UIColor(rgb:lamp.core).setFill();path.fill()
            ctx.restoreGState()
        }
    }
    private func raster(_ size:CGSize,_ scale:CGFloat,_ draw:()->Void)->CGImage {
        let format=UIGraphicsImageRendererFormat();format.scale=scale;format.preferredRange = .standard;format.opaque=false
        return UIGraphicsImageRenderer(size:size,format:format).image {_ in draw()}.cgImage!
    }
    private func ensureArtwork() {
        // SwiftUI can publish a frame/finish before UIKit lays out the controls.
        // Never key new-size artwork with the previous layout's geometry.
        guard !layoutDeferred,controls.count>6,previousLayoutBounds==bounds else{return}
        let scale=max(1,contentScaleFactor),key=ArtworkKey(bounds:bounds,scale:scale,finish:finish)
        guard key != artworkKey else{return}
        let started=UIResponsivenessProbe.shared.beginOperation()
        defer{UIResponsivenessProbe.shared.record("HardwarePanel.rasterizeArtwork",began:started)}
        let p=finish.palette,screen=controls[6].rect
        // One active size/scale/finish only: old images and layers are released.
        pressedArtwork.removeAll();indicatorArtwork.removeAll()
        for layers in [pressedLayers,indicatorLayers,lampLayers] {for value in layers.values{value.removeFromSuperlayer()}}
        pressedLayers.removeAll();indicatorLayers.removeAll();lampLayers.removeAll()
        artwork=raster(bounds.size,scale) {
            box(bounds.insetBy(dx:0.5,dy:0.5),17,p.body,p.bodyBottom,p.accent)
            box(keyboardRect,12,p.keybed,p.keybedBottom,0x262a2b)
            box(screen.insetBy(dx:-4,dy:-4),8,0x161b1e,0x090c0f,0x677374)
            text("FM–1",CGRect(x:screen.minX,y:screen.midY-32,width:screen.width,height:36),28,p.led,.light)
            text("CHOOSE FIRMWARE ↑",CGRect(x:screen.minX,y:screen.midY+13,width:screen.width,height:16),10,p.led)
            for c in controls {
                switch c.kind {
                case .master,.encoder:
                    let r=c.rect.insetBy(dx:3,dy:3)
                    box(c.rect,c.rect.width/2,0x171919,0x0e1010,0x575b5a)
                    box(r,r.width/2,0x303332,0x171a19,0x494d4b)
                    box(r.insetBy(dx:6,dy:6),r.width/2,0x292c2b,0x1b1e1d)
                    text(c.name,CGRect(x:c.rect.midX-45,y:c.rect.minY-15,width:90,height:13),10,p.ink,.semibold)
                case .key(let id):keyFace(c,id,false,p)
                case .screen:break
                }
            }
        }
        artworkLayer.frame=bounds;artworkLayer.contentsScale=scale;artworkLayer.contents=artwork
        screenLayer.frame=screen;screenLayer.contentsScale=scale
        for (i,c) in controls.enumerated() {
            switch c.kind {
            case .key(let id):
                let local=PanelControl(name:c.name,rect:CGRect(origin:.zero,size:c.rect.size),kind:c.kind)
                let image=raster(c.rect.size,scale) {keyFace(local,id,true,p)}
                pressedArtwork[i]=image
                let pressed=CALayer();pressed.name="Pressed key \(id)";pressed.frame=c.rect;pressed.contentsScale=scale;pressed.contents=image
                pressed.isHidden=true;layer.addSublayer(pressed);pressedLayers[i]=pressed
                let lamp=CALayer();lamp.name="Firmware lamp \(id)";lamp.frame=lampRect(c,id).insetBy(dx:-lampPadding,dy:-lampPadding)
                lamp.contentsScale=scale;lamp.contents=lampSprite(lamp.bounds.size,scale,p);lamp.opacity=0
                layer.addSublayer(lamp);lampLayers[id]=lamp
            case .master,.encoder:
                let image=raster(c.rect.size,scale) {
                    let r=CGRect(origin:.zero,size:c.rect.size).insetBy(dx:3,dy:3)
                    box(CGRect(x:r.midX-1.5,y:r.midY-r.height*0.41,width:3,height:r.height*0.25),1.5,0xf1f4f6,0xcfd4d8)
                }
                indicatorArtwork[i]=image
                let marker=CALayer();marker.name="Knob marker \(i)";marker.frame=c.rect;marker.contentsScale=scale;marker.contents=image
                layer.addSublayer(marker);indicatorLayers[i]=marker
            case .screen:break
            }
        }
        artworkPixelSize=CGSize(width:CGFloat(artwork!.width),height:CGFloat(artwork!.height))
        artworkKey=key;artworkBuildCount += 1
    }
    /// Display snapshots update small compositing layers, never the gradient artwork.
    func refreshDisplay() {
        CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        ensureArtwork();guard !layoutDeferred,controls.count>6,previousLayoutBounds==bounds else{return}
        let image=instrument?.screen
        if lastScreen !== image {screenLayer.contents=image;lastScreen=image}
        let leds=instrument?.leds ?? []
        for (i,c) in controls.enumerated() {
            switch c.kind {
            case .key(let id):
                let hidden = !held.contains(id)
                if pressedLayers[i]?.isHidden != hidden {pressedLayers[i]?.isHidden=hidden}
                let opacity=PanelPalette.lampOpacity(id<leds.count ? leds[id] : 0)
                if lampLayers[id]?.opacity != opacity {lampLayers[id]?.opacity=opacity}
            case .master,.encoder:
                let rotation:CGFloat
                if case .master=c.kind {rotation=CGFloat((instrument?.volume ?? 0.7)*270-135)*CGFloat.pi/180} else {rotation=angles[i] ?? -0.5}
                let transform=CGAffineTransform(rotationAngle:rotation)
                if indicatorLayers[i]?.affineTransform() != transform {indicatorLayers[i]?.setAffineTransform(transform)}
            case .screen:break
            }
        }
    }
    private func point(_ touch:UITouch)->CGPoint {touch.location(in:self)}
    private func hit(_ p:CGPoint)->Int? {
        // Preserve the exact visible target first. Keyboard gutters and the casing
        // below the keys belong to their nearest key too: a finger must not lose
        // its note just because it landed/slid a point into a drawing gap.
        if let exact=controls.indices.reversed().first(where:{controls[$0].rect.contains(p)}) {return exact}
        guard bounds.contains(p),p.y>=keyboardRect.minY else {return nil}
        return controls.indices.filter {i in
            if case .key(let id)=controls[i].kind {return id>=14};return false
        }.min {a,b in
            func distance(_ rect:CGRect)->CGFloat {
                let dx=max(0,max(rect.minX-p.x,p.x-rect.maxX)),dy=max(0,max(rect.minY-p.y,p.y-rect.maxY))
                return dx*dx+dy*dy
            }
            return distance(controls[a].rect)<distance(controls[b].rect)
        }
    }
    // The same resolver is exercised by geometry tests and actual touch tracking.
    func pianoKey(at point:CGPoint)->Int? {
        guard let i=hit(point),case .key(let id)=controls[i].kind,id>=14 else {return nil}
        return id
    }
    private func press(_ i:Int,_ down:Bool) {
        if case .key(let id)=controls[i].kind {
            if touchDiagnostics {
                if down {receipts[id,default:TouchReceipt()].downs += 1} else {receipts[id,default:TouchReceipt()].ups += 1}
            }
            let newlyPressed=down && !held.contains(id)
            if down {held.insert(id)} else {held.remove(id)}
            instrument?.key(id,down);refreshDisplay()
            if newlyPressed {haptics.button()}
        }
    }
    private func turn(_ i:Int,_ delta:Int) {
        var changed=false
        switch controls[i].kind {
        case .encoder(let id):
            guard delta != 0 else{return}
            angles[i,default:0] += CGFloat(delta)*0.10;instrument?.encoder(id,delta)
            changed=true
        case .master:
            guard let instrument else{return}
            let previous=instrument.volume,next=min(1,max(0,previous+Double(delta)*0.015))
            guard next != previous else{return}
            instrument.master(next)
            changed=UInt32(previous*1023) != UInt32(next*1023)
        default:break
        };refreshDisplay()
        if changed {haptics.detent()}
    }
    override func touchesBegan(_ input:Set<UITouch>,with event:UIEvent?) {
        guard !layoutDeferred,previousLayoutBounds==bounds else{return}
        haptics.prepareButton()
        for t in input {let p=point(t);if let i=hit(p) {
            let already=touches.values.contains{$0.0==i}
            touches[ObjectIdentifier(t)]=(i,p)
            switch controls[i].kind {
            case .master,.encoder:knobDragAnchors[ObjectIdentifier(t)]=PanelKnobDragAnchor()
            default:break
            }
            if touchDiagnostics,case .key(let id)=controls[i].kind {
                var receipt=receipts[id] ?? TouchReceipt()
                receipt.began += 1
                receipt.peakTouches=max(receipt.peakTouches,touches.values.filter{$0.0==i}.count)
                receipt.maxBeganDelay=max(receipt.maxBeganDelay,ProcessInfo.processInfo.systemUptime-t.timestamp)
                receipts[id]=receipt
            }
            if !already {press(i,true)}
        }}
    }
    override func touchesMoved(_ input:Set<UITouch>,with event:UIEvent?) {
        guard !layoutDeferred,previousLayoutBounds==bounds else{return}
        for t in input {
            let key=ObjectIdentifier(t);guard let (i,last)=touches[key] else{continue};let p=point(t)
            if i<0 {
                if let next=hit(p),case .key(let n)=controls[next].kind,n>=14 {
                    let already=touches.values.contains{$0.0==next};touches[key]=(next,p);if !already {press(next,true)}
                }
                continue
            }
            switch controls[i].kind {
            case .encoder,.master:
                let movement=knobDragAnchors[key,default:PanelKnobDragAnchor()].update(anchorY:last.y,currentY:p.y)
                touches[key]=(i,CGPoint(x:p.x,y:movement.anchorY))
                if movement.steps != 0 {turn(i,movement.steps)}
            case .key(let id) where id>=14:
                let next=hit(p)
                if next != i {
                    touches[key]=(-1,p)
                    if !touches.values.contains(where:{$0.0==i}) {press(i,false)}
                    if let next,case .key(let n)=controls[next].kind,n>=14 {
                        let already=touches.values.contains{$0.0==next};touches[key]=(next,p);if !already{press(next,true)}
                    }
                }
            default:break
            }
        }
    }
    override func touchesEnded(_ input:Set<UITouch>,with event:UIEvent?) {
        for t in input {
            knobDragAnchors.removeValue(forKey:ObjectIdentifier(t))
            if let (i,_)=touches.removeValue(forKey:ObjectIdentifier(t)),i>=0 {
            if touchDiagnostics,case .key(let id)=controls[i].kind {receipts[id,default:TouchReceipt()].ended += 1}
            if !touches.values.contains(where:{$0.0==i}) {press(i,false)}
            if case .screen=controls[i].kind,controls[i].rect.contains(point(t)){showScreen?();haptics.button()}
        }}
    }
    override func touchesCancelled(_ input:Set<UITouch>,with event:UIEvent?) {
        for t in input {
            knobDragAnchors.removeValue(forKey:ObjectIdentifier(t))
            if let (i,_)=touches.removeValue(forKey:ObjectIdentifier(t)),i>=0 {
            if touchDiagnostics,case .key(let id)=controls[i].kind {receipts[id,default:TouchReceipt()].cancelled += 1}
            if !touches.values.contains(where:{$0.0==i}) {press(i,false)}
        }}
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scale=window?.screen.scale {contentScaleFactor=scale}
        if window == nil {for id in held {instrument?.key(id,false)};held.removeAll();touches.removeAll();knobDragAnchors.removeAll()}
        else {haptics.prepareButton()}
        refreshDisplay()
    }
    override func traitCollectionDidChange(_ previousTraitCollection:UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.displayScale != traitCollection.displayScale {
            if let scale=window?.screen.scale {contentScaleFactor=scale}
            refreshDisplay()
        }
    }
}
