import SwiftUI
import UIKit

struct PanelView: UIViewRepresentable {
    @ObservedObject var instrument: Instrument
    var showScreen: () -> Void
    func makeUIView(context: Context) -> HardwarePanel {
        let view=HardwarePanel();view.instrument=instrument;view.showScreen=showScreen;return view
    }
    func updateUIView(_ view: HardwarePanel, context: Context) {view.instrument=instrument;view.setNeedsDisplay()}
}

private struct PanelControl {
    enum Kind {case key(Int), encoder(Int), master, screen}
    let name: String
    let rect: CGRect
    let kind: Kind
}
private final class AccessibleControl: UIAccessibilityElement {
    var activate: (() -> Void)?
    var adjust: ((Int) -> Void)?
    override func accessibilityActivate() -> Bool {activate?();return true}
    override func accessibilityIncrement() {adjust?(1)}
    override func accessibilityDecrement() {adjust?(-1)}
}

final class HardwarePanel: UIView {
    weak var instrument: Instrument?
    var showScreen: (() -> Void)?
    private var controls:[PanelControl]=[]
    private var touches:[ObjectIdentifier:(Int,CGPoint)]=[:]
    private var held:Set<Int>=[]
    private var angles:[Int:CGFloat]=[:]
    private let W:CGFloat=1000, H:CGFloat=590
    private var scale:CGFloat {min(bounds.width/W,bounds.height/H)}
    private var origin:CGPoint {CGPoint(x:(bounds.width-W*scale)/2,y:(bounds.height-H*scale)/2)}
    private let labels=["FX","SEL","ENV","LFO","EDIT","GLO","HOME","SAVE","ARP","SEQ","PLAY\nSTOP","REC"]
    private let whites=[0,2,4,6,7,9,11,12,14,16,18,19,21,23,24,26]
    private let blacks=[(1,0),(3,1),(5,2),(8,4),(10,5),(13,7),(15,8),(17,9),(20,11),(22,12),(25,14)]
    override init(frame:CGRect) {
        super.init(frame:frame);isOpaque=false;backgroundColor = .clear;isMultipleTouchEnabled=true
        controls=[
            PanelControl(name:"MASTER",rect:CGRect(x:51,y:65,width:56,height:56),kind:.master),
            PanelControl(name:"SELECT",rect:CGRect(x:161,y:65,width:56,height:56),kind:.encoder(0)),
            PanelControl(name:"PRESETS",rect:CGRect(x:51,y:169,width:56,height:56),kind:.encoder(6)),
            PanelControl(name:"ALGORITHM",rect:CGRect(x:161,y:169,width:56,height:56),kind:.encoder(1)),
            PanelControl(name:"OCT−",rect:CGRect(x:59,y:258,width:66,height:34),kind:.key(0)),
            PanelControl(name:"OCT+",rect:CGRect(x:139,y:258,width:66,height:34),kind:.key(1)),
            PanelControl(name:"Enlarge display",rect:CGRect(x:285,y:72,width:168,height:168),kind:.screen)
        ]
        for i in 0..<4 {controls.append(PanelControl(name:"KNOB\(i+1)",rect:CGRect(x:534+CGFloat(i)*112,y:65,width:56,height:56),kind:.encoder(i+2)))}
        for i in 0..<12 {controls.append(PanelControl(name:labels[i].replacingOccurrences(of:"\n",with:" "),rect:CGRect(x:548+CGFloat(i%6)*62,y:178+CGFloat(i/6)*62,width:51,height:51),kind:.key(i+2)))}
        for (i,n) in whites.enumerated() {controls.append(PanelControl(name:note(n),rect:CGRect(x:49+CGFloat(i)*57,y:458,width:43,height:92),kind:.key(n+14)))}
        for (n,after) in blacks {controls.append(PanelControl(name:note(n),rect:CGRect(x:78+CGFloat(after)*57,y:360,width:43,height:90),kind:.key(n+14)))}
    }
    required init?(coder:NSCoder){fatalError()}
    private func note(_ n:Int)->String {let midi=n+53;return ["C","C sharp","D","D sharp","E","F","F sharp","G","G sharp","A","A sharp","B"][midi%12]+"\(midi/12-1)"}
    override func layoutSubviews() {
        super.layoutSubviews()
        accessibilityElements=controls.enumerated().map {i,c in
            let a=AccessibleControl(accessibilityContainer:self)
            a.accessibilityLabel=c.name;a.accessibilityIdentifier=c.name
            a.accessibilityFrameInContainerSpace=CGRect(x:origin.x+c.rect.minX*scale,y:origin.y+c.rect.minY*scale,width:c.rect.width*scale,height:c.rect.height*scale)
            switch c.kind {
            case .master,.encoder: a.accessibilityTraits=[.adjustable];a.adjust={ [weak self] n in self?.turn(i,n) }
            default:a.accessibilityTraits=[.button];a.activate={ [weak self] in
                guard let self else{return}
                if case .screen=c.kind {self.showScreen?();return}
                self.press(i,true);DispatchQueue.main.asyncAfter(deadline:.now()+0.15){self.press(i,false)}
            }
            }
            return a
        }
    }
    private func color(_ value:UInt32, _ alpha:CGFloat=1)->UIColor {
        let r=CGFloat((value>>16)&255),g=CGFloat((value>>8)&255),b=CGFloat(value&255)
        // Hardware is neutral graphite; keep saturated status lights colored.
        if max(r,g,b)-min(r,g,b)<40 {return UIColor(white:(r*0.3+g*0.59+b*0.11)/255,alpha:alpha)}
        return UIColor(red:r/255,green:g/255,blue:b/255,alpha:alpha)
    }
    private func box(_ rect:CGRect,_ radius:CGFloat,_ top:UInt32,_ bottom:UInt32,_ stroke:UInt32?=nil) {
        let ctx=UIGraphicsGetCurrentContext()!
        let path=UIBezierPath(roundedRect:rect,cornerRadius:radius)
        ctx.saveGState();path.addClip()
        let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color(top).cgColor,color(bottom).cgColor] as CFArray,locations:[0,1])!
        ctx.drawLinearGradient(gradient,start:CGPoint(x:rect.midX,y:rect.minY),end:CGPoint(x:rect.midX,y:rect.maxY),options:[]);ctx.restoreGState()
        if let stroke {color(stroke).setStroke();path.lineWidth=1.4;path.stroke()}
    }
    private func text(_ value:String,_ rect:CGRect,_ size:CGFloat=12,_ tint:UInt32=0xc8c9c7,_ weight:UIFont.Weight = .medium) {
        let style=NSMutableParagraphStyle();style.alignment = .center
        (value as NSString).draw(in:rect,withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color(tint),.paragraphStyle:style])
    }
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext() else{return}
        ctx.saveGState();ctx.translateBy(x:origin.x,y:origin.y);ctx.scaleBy(x:scale,y:scale)
        ctx.setShadow(offset:CGSize(width:0,height:9),blur:16,color:UIColor.black.withAlphaComponent(0.6).cgColor)
        box(CGRect(x:4,y:4,width:992,height:582),52,0x454746,0x272a29,0x686b68)
        ctx.setShadow(offset:.zero,blur:0,color:nil)
        box(CGRect(x:10,y:10,width:980,height:568),46,0x454745,0x333633,0x181b19)
        // Fine deterministic surface grain drawn in native Core Graphics.
        for y in stride(from:20,to:570,by:5) {for x in stride(from:20,to:980,by:5) {
            let v=(x*17+y*31)%19;ctx.setFillColor(UIColor.white.withAlphaComponent(v<3 ? 0.027 : 0.006).cgColor);ctx.fill(CGRect(x:x,y:y,width:1,height:1))
        }}
        box(CGRect(x:255,y:43,width:228,height:245),32,0x0c100f,0x050807,0x535753)
        box(CGRect(x:276,y:63,width:186,height:186),5,0x050909,0x030605)
        if let screen=instrument?.screen {
            ctx.saveGState();ctx.interpolationQuality = .none
            ctx.translateBy(x:285,y:240);ctx.scaleBy(x:1,y:-1)
            ctx.draw(screen,in:CGRect(x:0,y:0,width:168,height:168));ctx.restoreGState()
        } else {
            text("FM–1",CGRect(x:290,y:105,width:158,height:35),29,0xb1d7d0,.light)
            text("LOAD FIRMWARE",CGRect(x:290,y:159,width:158,height:22),11,0x728d87)
            text(".fwsc",CGRect(x:290,y:184,width:158,height:20),11,0x65736e)
        }
        text("FM–1",CGRect(x:288,y:261,width:162,height:15),12,0x78807a,.semibold)
        box(CGRect(x:533,y:164,width:392,height:141),18,0x282c29,0x151917,0x6b6f69)
        box(CGRect(x:49,y:249,width:166,height:51),9,0x1a1e1b,0x131713,0x656a62)
        box(CGRect(x:33,y:340,width:934,height:221),36,0x252a26,0x181e19,0x767b72)
        let led=instrument?.leds ?? []
        for (i,c) in controls.enumerated() {
            switch c.kind {
            case .master,.encoder:
                let r=c.rect.insetBy(dx:6,dy:6)
                box(r.insetBy(dx:-4,dy:-4),26,0x171b18,0x090d0a,0x686e65)
                box(r,22,0x5d625b,0x222821,0x82887b)
                box(r.insetBy(dx:6,dy:6),18,0x42493f,0x2b3228)
                ctx.saveGState();ctx.translateBy(x:r.midX,y:r.midY)
                let rotation:CGFloat
                if case .master=c.kind {rotation = CGFloat((instrument?.volume ?? 0.7)*270-135)*CGFloat.pi/180} else {rotation=angles[i] ?? -0.5}
                ctx.rotate(by:rotation);box(CGRect(x:-2,y:-18,width:4,height:11),2,0xe4e9db,0xb6c5ae);ctx.restoreGState()
                text(c.name,CGRect(x:c.rect.midX-55,y:c.rect.minY-24,width:110,height:18),12,0xc5cac1,.regular)
            case .key(let id):
                let down=held.contains(id);let active=id<led.count && led[id]>0.08
                if id>=14 {
                    box(c.rect.insetBy(dx:-3,dy:-2),23,0x101610,0x101610,0x626b5c)
                    box(c.rect,20,down ? 0x53634c : 0x343d31,down ? 0x394c33 : 0x242e22,down ? 0xb6d69c : 0x4d5845)
                    let line=CGRect(x:c.rect.midX-2.5,y:c.rect.minY+14,width:5,height:c.rect.height>90 ? 48 : 31)
                    box(line,2.5,active || down ? 0xc1ff8c : 0xf3f5e9,active || down ? 0x72cd4b : 0xc4cebc)
                    if let k=blacks.firstIndex(where:{$0.0 == id-14}),k<10 {
                        let words=["OP1","OP2","OP3","OP4","OP5","OP6","PIT","GLO","MONO","POLY"]
                        text(words[k],CGRect(x:c.rect.minX,y:c.rect.minY+57,width:c.rect.width,height:12),9,0xc2ccba,.regular)
                    }
                } else {
                    box(c.rect.insetBy(dx:-2,dy:-2),9,0x0a100a,0x0b110a)
                    box(c.rect,7,down ? 0x56644d : 0x343e2f,down ? 0x35442e : 0x1d2818,0x535e4b)
                    let title=id<2 ? c.name : labels[id-2]
                    text(title,CGRect(x:c.rect.minX+2,y:c.rect.midY-(title.contains("\n") ? 16 : 7),width:c.rect.width-4,height:35),11,0xd4ddca,.medium)
                    if active {box(CGRect(x:c.rect.midX-7,y:c.rect.minY+3,width:14,height:2),1,0xc1ff8c,0x72cd4b)}
                }
            case .screen:break
            }
        }
        ctx.restoreGState()
    }
    private func point(_ touch:UITouch)->CGPoint {let p=touch.location(in:self);return CGPoint(x:(p.x-origin.x)/scale,y:(p.y-origin.y)/scale)}
    private func hit(_ p:CGPoint)->Int? {controls.indices.reversed().first{controls[$0].rect.insetBy(dx:-3,dy:-3).contains(p)}}
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
            if i < 0 {
                if let next=hit(p),case .key(let n)=controls[next].kind,n>=14 {
                    let already=touches.values.contains{$0.0==next};touches[key]=(next,p);if !already {press(next,true)}
                }
                continue
            }
            switch controls[i].kind {
            case .encoder,.master:
                let delta=Int((last.y-p.y)/4)
                if delta != 0 {turn(i,delta);touches[key]=(i,CGPoint(x:p.x,y:last.y-CGFloat(delta)*4))}
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
