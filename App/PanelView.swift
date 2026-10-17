import SwiftUI
import UIKit

// Names and pairings follow M-VAVE's FM-1 product color selector.
enum PanelFinish: String, CaseIterable, Identifiable {
    case black = "Black", purple = "Purple", orange = "Orange", blackGreen = "Black-Green", coolGray = "Cool Gray", whiteBlue = "White-Blue"
    var id: String { rawValue }
    var palette: PanelPalette {
        switch self {
        case .black: return PanelPalette(body:0x383a3b, bodyBottom:0x252729, accent:0xb8bec0, control:0x484c50, controlBottom:0x25292c, ink:0xe0e3e4)
        case .purple: return PanelPalette(body:0xe2b6d4, bodyBottom:0xc294bf, accent:0x9b77cb, control:0x9871bb, controlBottom:0x6f4e96, ink:0x392e46)
        case .orange: return PanelPalette(body:0xf26c30, bodyBottom:0xd84d22, accent:0xffc497, control:0x494445, controlBottom:0x2b292b, ink:0x2d2422)
        case .blackGreen: return PanelPalette(body:0x343839, bodyBottom:0x222829, accent:0x6cd1b5, control:0x74c9b1, controlBottom:0x409782, ink:0xddebe7)
        case .coolGray: return PanelPalette(body:0xd6d0bd, bodyBottom:0xbeb8a8, accent:0xe7e3d7, control:0x999a91, controlBottom:0x74776f, ink:0x363c39)
        case .whiteBlue: return PanelPalette(body:0xf0f0e9, bodyBottom:0xd6dbd8, accent:0x6e9bcd, control:0x6f91bb, controlBottom:0x466a97, ink:0x34455a)
        }
    }
    var swatch: Color { Color(uiColor:UIColor(rgb:palette.body)) }
    var secondarySwatch: Color { Color(uiColor:UIColor(rgb:palette.control)) }
}
struct PanelPalette {
    let body:UInt32, bodyBottom:UInt32, accent:UInt32, control:UInt32, controlBottom:UInt32, ink:UInt32
}
private extension UIColor {
    convenience init(rgb:UInt32, alpha:CGFloat=1) {self.init(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)}
}
struct PanelView: UIViewRepresentable {
    @ObservedObject var instrument: Instrument
    var finish: PanelFinish = .black
    var showScreen: () -> Void
    func makeUIView(context: Context) -> HardwarePanel {
        let view=HardwarePanel();view.instrument=instrument;view.finish=finish;view.showScreen=showScreen;return view
    }
    func updateUIView(_ view: HardwarePanel, context: Context) {view.instrument=instrument;view.finish=finish;view.showScreen=showScreen;view.setNeedsDisplay()}
}
private struct PanelControl {
    enum Kind {case key(Int), encoder(Int), master, screen}
    let name:String, rect:CGRect, kind:Kind
}
private final class AccessibleControl:UIAccessibilityElement {
    var activate:(() -> Void)?
    var adjust:((Int) -> Void)?
    override func accessibilityActivate()->Bool {activate?();return true}
    override func accessibilityIncrement(){adjust?(1)}
    override func accessibilityDecrement(){adjust?(-1)}
}
final class HardwarePanel:UIView {
    weak var instrument:Instrument?
    var finish:PanelFinish = .black
    var showScreen:(() -> Void)?
    private var controls:[PanelControl]=[]
    private var touches:[ObjectIdentifier:(Int,CGPoint)]=[:]
    private var held:Set<Int>=[]
    private var angles:[Int:CGFloat]=[:]
    private var keyboardRect=CGRect.zero
    private let labels=["FX","SEL","ENV","LFO","EDIT","GLO","HOME","SAVE","ARP","SEQ","PLAY\nSTOP","REC"]
    private let whites=[0,2,4,6,7,9,11,12,14,16,18,19,21,23,24,26]
    private let blacks=[(1,0),(3,1),(5,2),(8,4),(10,5),(13,7),(15,8),(17,9),(20,11),(22,12),(25,14)]
    override init(frame:CGRect) {super.init(frame:frame);isOpaque=false;backgroundColor = .clear;isMultipleTouchEnabled=true}
    required init?(coder:NSCoder){fatalError()}
    private func note(_ n:Int)->String {let midi=n+53;return ["C","C sharp","D","D sharp","E","F","F sharp","G","G sharp","A","A sharp","B"][midi%12]+"\(midi/12-1)"}
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width>0,bounds.height>0 else{return}
        // Lay out directly in screen points: the phone's wide canvas is an instrument,
        // rather than a small scale model centered inside a fixed hardware aspect ratio.
        let w=bounds.width, h=bounds.height
        let keyboardHeight=min(240,max(118,h*0.42)), upper=h-keyboardHeight-8
        let left=w*0.235, screenWidth=w*0.23, rightX=left+screenWidth+12, rightWidth=w-rightX-12
        let knob=min(90,min((left-22)/2,(upper-88)/2))
        let secondY=upper-44-knob
        let screenSize=min(screenWidth-12,upper-16)
        controls=[
            PanelControl(name:"MASTER",rect:CGRect(x:9,y:19,width:knob,height:knob),kind:.master),
            PanelControl(name:"SELECT",rect:CGRect(x:left-knob-7,y:19,width:knob,height:knob),kind:.encoder(0)),
            PanelControl(name:"PRESETS",rect:CGRect(x:9,y:secondY,width:knob,height:knob),kind:.encoder(6)),
            PanelControl(name:"ALGORITHM",rect:CGRect(x:left-knob-7,y:secondY,width:knob,height:knob),kind:.encoder(1)),
            PanelControl(name:"OCT−",rect:CGRect(x:9,y:upper-39,width:(left-22)/2,height:36),kind:.key(0)),
            PanelControl(name:"OCT+",rect:CGRect(x:13+(left-22)/2,y:upper-39,width:(left-22)/2,height:36),kind:.key(1)),
            PanelControl(name:"Enlarge display",rect:CGRect(x:left+4+(screenWidth-12-screenSize)/2,y:12,width:screenSize,height:screenSize),kind:.screen)
        ]
        let rightKnob=min(90,min((rightWidth-30)/4,upper*0.36))
        for i in 0..<4 {
            let slot=rightWidth/4
            controls.append(PanelControl(name:"KNOB\(i+1)",rect:CGRect(x:rightX+slot*CGFloat(i)+(slot-rightKnob)/2,y:19,width:rightKnob,height:rightKnob),kind:.encoder(i+2)))
        }
        let functionTop=max(rightKnob+26,upper*0.51), gap:CGFloat=5
        let buttonWidth=(rightWidth-gap*5)/6, buttonHeight=(upper-functionTop-gap-3)/2
        for i in 0..<12 {controls.append(PanelControl(name:labels[i].replacingOccurrences(of:"\n",with:" "),rect:CGRect(x:rightX+CGFloat(i%6)*(buttonWidth+gap),y:functionTop+CGFloat(i/6)*(buttonHeight+gap),width:buttonWidth,height:buttonHeight),kind:.key(i+2)))}
        keyboardRect=CGRect(x:3,y:upper+5,width:w-6,height:keyboardHeight+1)
        let pitch=(w-16)/16, keyWidth=pitch-2
        for (i,n) in whites.enumerated() {controls.append(PanelControl(name:note(n),rect:CGRect(x:8+CGFloat(i)*pitch,y:upper+8+keyboardHeight*0.48,width:keyWidth,height:keyboardHeight*0.52-4),kind:.key(n+14)))}
        for (n,after) in blacks {controls.append(PanelControl(name:note(n),rect:CGRect(x:8+pitch*0.64+CGFloat(after)*pitch,y:upper+10,width:keyWidth,height:keyboardHeight*0.43),kind:.key(n+14)))}
        accessibilityElements=controls.enumerated().map {i,c in
            let a=AccessibleControl(accessibilityContainer:self)
            a.accessibilityLabel=c.name;a.accessibilityIdentifier=c.name;a.accessibilityFrameInContainerSpace=c.rect
            switch c.kind {
            case .master,.encoder:a.accessibilityTraits=[.adjustable];a.accessibilityHint="Swipe up or down to turn";a.adjust={ [weak self] n in self?.turn(i,n) }
            default:a.accessibilityTraits=[.button];a.activate={ [weak self] in
                guard let self else{return}
                if case .screen=c.kind {self.showScreen?();return}
                self.press(i,true);DispatchQueue.main.asyncAfter(deadline:.now()+0.15){self.press(i,false)}
            }
            }
            return a
        }
        setNeedsDisplay()
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
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext(),controls.count>6 else{return}
        let p=finish.palette
        box(bounds.insetBy(dx:0.5,dy:0.5),17,p.body,p.bodyBottom,p.accent)
        box(keyboardRect,12,0x1b2022,0x111618,0x616b6d)
        let screen=controls[6].rect
        box(screen.insetBy(dx:-4,dy:-4),8,0x161b1e,0x090c0f,0x677374)
        if let image=instrument?.screen {
            ctx.saveGState();ctx.interpolationQuality = .none
            ctx.translateBy(x:screen.minX,y:screen.maxY);ctx.scaleBy(x:1,y:-1)
            ctx.draw(image,in:CGRect(origin:.zero,size:screen.size));ctx.restoreGState()
        } else {
            text("FM–1",CGRect(x:screen.minX,y:screen.midY-32,width:screen.width,height:36),28,0xc9e4df,.light)
            text("CHOOSE FIRMWARE ↑",CGRect(x:screen.minX,y:screen.midY+13,width:screen.width,height:16),10,0x94b9b2)
        }
        let led=instrument?.leds ?? []
        for (i,c) in controls.enumerated() {
            switch c.kind {
            case .master,.encoder:
                let r=c.rect.insetBy(dx:3,dy:3)
                box(c.rect,c.rect.width/2,0x161c1f,0x0b1013,p.accent)
                box(r,r.width/2,p.control,p.controlBottom,p.accent)
                box(r.insetBy(dx:6,dy:6),r.width/2,p.control,p.controlBottom)
                ctx.saveGState();ctx.translateBy(x:r.midX,y:r.midY)
                let rotation:CGFloat
                if case .master=c.kind {rotation=CGFloat((instrument?.volume ?? 0.7)*270-135)*CGFloat.pi/180} else {rotation=angles[i] ?? -0.5}
                ctx.rotate(by:rotation);box(CGRect(x:-1.5,y:-r.height*0.41,width:3,height:r.height*0.25),1.5,0xf1f6f1,0xc5d8cf);ctx.restoreGState()
                text(c.name,CGRect(x:c.rect.midX-45,y:c.rect.minY-15,width:90,height:13),10,p.ink,.semibold)
            case .key(let id):
                let down=held.contains(id), active=id<led.count && led[id]>0.08
                if id>=14 {
                    box(c.rect,9,down ? 0x688f83 : p.control,down ? 0x36574d : p.controlBottom,down ? 0xa3ffd7 : p.accent)
                    box(CGRect(x:c.rect.midX-2,y:c.rect.minY+10,width:4,height:max(16,c.rect.height*0.4)),2,active || down ? 0xbaffad : 0xf0f3e8,active || down ? 0x68db68 : 0xc7d0c7)
                    if let k=blacks.firstIndex(where:{$0.0==id-14}),k<10,c.rect.height>45 {
                        text(["OP1","OP2","OP3","OP4","OP5","OP6","PIT","GLO","MONO","POLY"][k],CGRect(x:c.rect.minX,y:c.rect.maxY-16,width:c.rect.width,height:12),9,0xf0f2eb)
                    }
                } else {
                    box(c.rect,7,down ? 0x688f83 : p.control,down ? 0x36574d : p.controlBottom,down ? 0xa3ffd7 : p.accent)
                    let title=id<2 ? c.name : labels[id-2]
                    text(title,CGRect(x:c.rect.minX+1,y:c.rect.midY-(title.contains("\n") ? 12 : 6),width:c.rect.width-2,height:28),id<2 ? 12 : 11,0xf6f7f1,.semibold)
                    if active {box(CGRect(x:c.rect.midX-7,y:c.rect.minY+3,width:14,height:2),1,0xc1ff8c,0x72cd4b)}
                }
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
            if down {held.insert(id)} else {held.remove(id)}
            instrument?.key(id,down);setNeedsDisplay()
        }
    }
    private func turn(_ i:Int,_ delta:Int) {
        switch controls[i].kind {
        case .encoder(let id):angles[i,default:0] += CGFloat(delta)*0.10;instrument?.encoder(id,delta)
        case .master:instrument?.master((instrument?.volume ?? 0.7)+Double(delta)*0.015)
        default:break
        };setNeedsDisplay()
    }
    override func touchesBegan(_ input:Set<UITouch>,with event:UIEvent?) {
        for t in input {let p=point(t);if let i=hit(p) {
            let already=touches.values.contains{$0.0==i}
            touches[ObjectIdentifier(t)]=(i,p)
            if !already {press(i,true)}
        }}
    }
    override func touchesMoved(_ input:Set<UITouch>,with event:UIEvent?) {
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
                let delta=Int((last.y-p.y)/3)
                if delta != 0 {turn(i,delta);touches[key]=(i,CGPoint(x:p.x,y:last.y-CGFloat(delta)*3))}
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
        for t in input {if let (i,_)=touches.removeValue(forKey:ObjectIdentifier(t)),i>=0 {
            if !touches.values.contains(where:{$0.0==i}) {press(i,false)}
            if case .screen=controls[i].kind,controls[i].rect.contains(point(t)){showScreen?()}
        }}
    }
    override func touchesCancelled(_ input:Set<UITouch>,with event:UIEvent?) {
        for t in input {if let (i,_)=touches.removeValue(forKey:ObjectIdentifier(t)),i>=0,!touches.values.contains(where:{$0.0==i}) {press(i,false)}}
    }
    override func didMoveToWindow() {if window==nil {for id in held {instrument?.key(id,false)};held.removeAll();touches.removeAll()}}
}
