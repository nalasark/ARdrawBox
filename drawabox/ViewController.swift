//  ViewController.swift
//  drawabox
//
//  Created by pappar on 09/03/2018.
//  Copyright © 2018 zou yun. All rights reserved.

import UIKit
import SceneKit
import ARKit


class ViewController: UIViewController, ARSCNViewDelegate, UIGestureRecognizerDelegate {

    // --- INTERFACE BUILDER CONNECTIONS

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var searchingLabel: UILabel!
    @IBOutlet weak var heightSlider: UISlider!
 
    var spheres: [SCNNode] = [] // Spheres nodes
    var measurementLabel = UILabel() // Measurement label
    
    var focalNode: FocalNode?
    private var screenCenter: CGPoint!
    
    let planeIdentifiers = [UUID]()
    var anchors = [ARAnchor]()
    var nodes = [SCNNode]()
    
    var planeNodesCount = 0 // keep track of number of anchor nodes that are added into the scene
    
    let planeHeight: CGFloat = 0.01
    
    var isFloorPlaneRendered = false
    

    var center : SCNVector3?
    let formatter = NumberFormatter()

    @IBAction func heightchanged(_ sender: UISlider) {
        let heightd=sender.value
        box.move(side: .top, to: heightd)
    }

    var box: Box!
    var hitTestPlane: SCNNode!
    var floor: SCNNode!
    
    var currentAnchor: ARAnchor?
    
    //UNCLEAR
    struct RenderingCategory: OptionSet {
        let rawValue: Int
        static let reflected = RenderingCategory(rawValue: 1 << 1)//1 shift left by 1 place
        static let planes = RenderingCategory(rawValue: 1 << 2) //1 shift left by 2?
    }
    
    //UNCLEAR
    var planesShown: Bool {
        get {
            return RenderingCategory(rawValue: sceneView.pointOfView!.camera!.categoryBitMask).contains(.planes)
        }
        set {
            var mask = RenderingCategory(rawValue: sceneView.pointOfView!.camera!.categoryBitMask)
            if newValue == true {
                mask.formUnion(.planes)
            } else {
                mask.subtract(.planes)
            }
            sceneView.pointOfView!.camera!.categoryBitMask = mask.rawValue
        }
    }
    
    // ---------------------------------------------------
    // --- VIEW HANDLERS
    
    //On View Loaded
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //set the view's delegate
        sceneView.delegate = self
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = true
        
        screenCenter = view.center
        heightSlider.isHidden=true // hide height slider
        
        //set gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.numberOfTapsRequired = 1 // Sets the amount of taps needed to trigger the handler
        sceneView.addGestureRecognizer(panGesture)
        sceneView.addGestureRecognizer(tapGesture)
        
        //initialize box (& floor)
        initBox()
    }

    //Before View Added
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal

        sceneView.session.run(configuration, options: [ARSession.RunOptions.removeExistingAnchors,ARSession.RunOptions.resetTracking])
    }
    
    //Before View Removed
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sceneView.session.pause() // Pause the view's session
    }
    
    // ---------------------------------------------------
    // --- INTERACTION MODE HANDLERS
    
    enum InteractionMode {
        case detectingFloor
        case waitingForLocation
        case draggingInitialWidth, draggingInitialLength
        case waitingForFaceDrag, draggingFace(side: Box.Side, dragStart: SCNVector3)
    }
    
    //For each interaction mode
    var mode: InteractionMode = .detectingFloor {
        didSet {
            switch mode {
            case .detectingFloor, .waitingForLocation:
                box.isHidden = true
                box.clearHighlights()
                hitTestPlane.isHidden = true
                floor.isHidden = true
                
                planesShown = false
                
            case .draggingInitialWidth, .draggingInitialLength:
                
                box.isHidden = false
                box.clearHighlights()
                floor.isHidden = false
                
                // Place the hit-test plane flat on the z-axis, aligned with the bottom of the box.
                hitTestPlane.isHidden = false
                hitTestPlane.position = .zero
                hitTestPlane.boundingBox.min = SCNVector3(x: -1000, y: 0, z: -1000)
                hitTestPlane.boundingBox.max = SCNVector3(x: 1000, y: 0, z: 1000)
                //hitTestPlane.boundingBox.min = SCNVector3(x: -Float(Double.infinity), y: 0, z: -Float(Double.infinity))
                //hitTestPlane.boundingBox.max = SCNVector3(x: Float(Double.infinity), y: 0, z: Float(Double.infinity))
                
                planesShown = false
                
            case .waitingForFaceDrag:
                
                box.isHidden = false
                box.clearHighlights()
                floor.isHidden = false
                hitTestPlane.isHidden = true
                
                planesShown = false
                
            case .draggingFace(let side, let dragStart):
                
                box.isHidden = false
                floor.isHidden = false
                hitTestPlane.isHidden = false
                hitTestPlane.position = dragStart
                
                planesShown = false
                
                box.highlight(side: side)
                
                switch side.axis {
                case .x:
                    hitTestPlane.boundingBox.min = SCNVector3(x: -1000, y: -1000, z: 0)
                    hitTestPlane.boundingBox.max = SCNVector3(x: 1000, y: 1000, z: 0)
                case .y:
                    hitTestPlane.boundingBox.min = SCNVector3(x: -1000, y: -1000, z: 0)
                    hitTestPlane.boundingBox.max = SCNVector3(x: 1000, y: 1000, z: 0)
                case .z:
                    hitTestPlane.boundingBox.min = SCNVector3(x: 0, y: -1000, z: -1000)
                    hitTestPlane.boundingBox.max = SCNVector3(x: 0, y: 1000, z: 1000)
                }
            }
        }
    }
    
    // ---------------------------------------------------
    // --- INPUT HANDLERS (TAP/PAN)
    
    // On Tap
    @objc dynamic func handleTap(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch mode {
        case .waitingForLocation:
            getStartingLocation()
        case .draggingInitialWidth:
            handleInitialWidthDrag()
        case .draggingInitialLength:
            handleInitialLengthDrag()
        case .waitingForFaceDrag:
            findFaceDragLocation(gestureRecognizer)
        default:
            break
        }
    }
    
    // On Pan (finger-pan)
    @objc dynamic func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch mode {
        case .draggingFace:
            handleFaceDrag(gestureRecognizer)
        default:
            break
        }
    }
    
    // ---------------------------------------------------
    // --- HIT TEST FUNCTIONS
    
    func scenekitHit(at screenPos: CGPoint, within rootNode: SCNNode) -> SCNVector3? {
        let hits = sceneView.hitTest(screenPos, options: [
            .boundingBoxOnly: true,
            .firstFoundOnly: true,
            .rootNode: rootNode,
            .ignoreChildNodes: true
            ])
        return hits.first?.worldCoordinates
    }
    
    func realWorldHit(at screenPos: CGPoint) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {

        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)
        
        let planeHitTestResults = sceneView.hitTest(screenPos, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {
            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let planeAnchor = result.anchor
            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }
        
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.
        
        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false
        
        let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(screenPos, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
        
        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }
        
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.
        
        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }

        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.
        
        let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(screenPos)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }
        
        return (nil, nil, false)
    }
    
    // ---------------------------------------------------
    // --- RENDERERS

    // Called when an AR anchor is added to provide a respective Scenekit node
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        
        // add anchor node only if plane is not selected.
        //guard !isPlaneSelected else {
        //    sceneView.session.remove(anchor: anchor)
        //    return nil
        //}
        
        switch(mode){
        case .detectingFloor, .waitingForLocation:
            return renderFloorPlane(anchor: anchor)
        default: return nil
        }

    }
    
    // Called when an AR anchor has been updated with data from the given anchor
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        switch(mode){
        case .detectingFloor, .waitingForLocation:
            updateFloorPlane(node: node, anchor: anchor)
        default: return
        }
        
    }
    
    // Fixed Update
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {

        switch(mode){
        case .waitingForLocation:
            updateFocalNodePos()
            
        case .draggingInitialWidth:
            updateInitialWidth()

        case .draggingInitialLength:
            updateInitialLength()

        default: break
        }
    }
    
    // called when a scenekit node corresponding to a new AR anchor has been added to the scene
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        switch(mode){
        case .detectingFloor:
            floorDetected()
            
        default: break
        }

        planeNodesCount += 1
        if node.childNodes.count > 0 && planeNodesCount % 2 == 0 {
            node.childNodes[0].geometry?.firstMaterial?.diffuse.contents = UIColor.yellow
        }
    }
    
    // ---------------------------------------------------
    // --- MISC FUNCTIONS
    
    func initBox() {
        box = Box()
        box.isHidden = true
        sceneView.scene.rootNode.addChildNode(box)
        
        //initialize hitTestPlane
        // Create an invisible plane used for hit-testing during drag operations. Child of box, inherits box's transform. Resized and repositioned within box depending on what part of box is being dragged.
        hitTestPlane = SCNNode()
        hitTestPlane.isHidden = true
        box.addChildNode(hitTestPlane)
        
        //set floor surface
        let floorSurface = SCNFloor()
        floorSurface.reflectivity = 0.2
        floorSurface.reflectionFalloffEnd = 0.05
        floorSurface.reflectionCategoryBitMask = RenderingCategory.reflected.rawValue
        // Floor scene reflections are blended with the diffuse color's transparency mask, so if diffuse is transparent then no reflection will be shown. To get around this, we make the floor black and use additive blending so that only the brighter reflection is shown.
        floorSurface.firstMaterial?.diffuse.contents = UIColor.black
        floorSurface.firstMaterial?.writesToDepthBuffer = false
        floorSurface.firstMaterial?.blendMode = .add
        floor = SCNNode(geometry: floorSurface)
        floor.isHidden = true
        box.addChildNode(floor)
        box.categoryBitMask |= RenderingCategory.reflected.rawValue
    }
    
    func resetBox() {
        mode = .waitingForLocation
        box.resizeTo(min: .zero, max: .zero)
        currentAnchor = nil
    }
    
    func renderFloorPlane(anchor: ARAnchor) -> SCNNode? {
        
        if isFloorPlaneRendered { return nil }
        
        guard let planeAnchor = anchor as? ARPlaneAnchor else {
            return nil
        }
        
        let plane = SCNBox(width: CGFloat(planeAnchor.extent.x),
                           height: 0.0001,
                           length: CGFloat(planeAnchor.extent.z), chamferRadius: 0)
        
        if let material = plane.firstMaterial {
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.yellow
            material.transparency = 0.2
            material.writesToDepthBuffer = false
        }
        
        let node = SCNNode(geometry: plane)
        node.categoryBitMask = RenderingCategory.planes.rawValue
        anchors.append(planeAnchor)
        
        isFloorPlaneRendered = true
        
        return node
    }
    
    func updateFloorPlane(node: SCNNode, anchor:ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor, let plane = node.geometry as? SCNBox else { return }
        
        //update floor plan size
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.length = CGFloat(planeAnchor.extent.z)
        
        // If this anchor is the one the box is positioned relative to, then update the box to match any corrections to the plane's observed position.
        if plane == currentAnchor {
            let oldPos = node.position
            let newPos = SCNVector3.positionFromTransform(planeAnchor.transform)
            let delta = newPos - oldPos
            box.position += delta
        }
        node.transform = SCNMatrix4(planeAnchor.transform)
        node.pivot = SCNMatrix4(translationByX: -planeAnchor.center.x, y: -planeAnchor.center.y, z: -planeAnchor.center.z)
    }
    
    // ---------------------------------------------------
    // --- MODE: DETECTING FLOOR (FUNCTIONS)
    
    func floorDetected() {
        drawFocalNode()
        hideSearchingForFloorLabel()
        mode = .waitingForLocation
    }
    
    func drawFocalNode() {
        guard focalNode == nil else { return }
        let node = FocalNode() // Create new focal node
        sceneView.scene.rootNode.addChildNode(node) // Add it to the root of our current scene
        self.focalNode = node // Store the focal node
    }
    
    func hideSearchingForFloorLabel() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.5,
                           animations: { self.searchingLabel.alpha = 0.0 },
                           completion: { _ in self.searchingLabel.isHidden = true }
            )
        }
    }
    
    // ----------------------------------------------------
    // --- MODE: WAITING FOR LOCATION (FUNCTIONS)
    
    // called in fixed update
    func updateFocalNodePos() {
        guard focalNode != nil else { return }

        let hit = sceneView.hitTest(screenCenter, types: .existingPlane)
        guard let positionColumn = hit.first?.worldTransform.columns.3 else { return }
        
        let pos = SCNVector3(x: positionColumn.x, y: positionColumn.y, z: positionColumn.z)
        self.focalNode!.position = pos
    }
    
    // called on tap - end check
    func getStartingLocation() {
        // Use real-world ARKit coordinates to determine where to start drawing.
        let hit = realWorldHit(at: screenCenter)
        // Once the user hits a usable real-world plane, switch into line-dragging mode.
        if let startPos = hit.position, let plane = hit.planeAnchor {
            box.position = startPos
            currentAnchor = plane
            mode = .draggingInitialWidth
        }
    }
    
    // ---------------------------------------------------
    // --- MODE: DRAGGING INITIAL WIDTH (FUNCTIONS)
    
    // called in fixed update
    func updateInitialWidth() {
        if let locationInWorld = scenekitHit(at: screenCenter, within: hitTestPlane) {
            //calculate width
            let delta = box.position - locationInWorld
            let distance = delta.length
            //calculate rotation
            let angleInRadians = atan2(delta.z, delta.x) //box's front will face 90 degrees CW out from line
            
            box.move(side: .right, to: distance)
            box.rotation = SCNVector4(x: 0, y: 1, z: 0, w: -(angleInRadians + Float.pi))
        }
    }
    
    // called on tap - end check
    func handleInitialWidthDrag() {
        // If the box ended up with a usable width, switch to length-dragging mode.
        // Otherwise, give up on this drag and start again.
        if abs(box.boundingBox.max.x - box.boundingBox.min.x) >= box.minLabelDistanceThreshold {
            mode = .draggingInitialLength
        } else {
            resetBox()
        }
    }
    
    // ---------------------------------------------------
    // --- MODE: DRAGGING INITIAL LENGTH (FUNCTIONS)
    
    // called in fixed update
    func updateInitialLength() {
        if let locationInWorld = scenekitHit(at: screenCenter, within: hitTestPlane) {
            // Convert hit position to box local coordinate system
            let locationInBox = box.convertPosition(locationInWorld, from: nil)
            
            // Front side faces toward +z, back side toward -z
            if locationInBox.z < 0 {
                box.move(side: .front, to: 0)
                box.move(side: .back, to: locationInBox.z)
            } else {
                box.move(side: .front, to: locationInBox.z)
                box.move(side: .back, to: 0)
            }
        }
    }
    
    // called on tap - end check
    func handleInitialLengthDrag() {
        // Once the box has a usable width and depth, switch to face-dragging mode.
        // Otherwise, stay in length-dragging mode.
        if (box.boundingBox.max.z - box.boundingBox.min.z) >= box.minLabelDistanceThreshold {
            focalNode?.isHidden=true
            heightSlider.isHidden=false
            mode = .waitingForFaceDrag
        }
    }
    
    // ---------------------------------------------------
    // --- MODE: WAITING FOR FACE DRAG (FUNCTIONS)
    
    // called on tap - check if face of box is tapped
    func findFaceDragLocation(_ gestureRecognizer: UIPanGestureRecognizer) {
        let touchPos = gestureRecognizer.location(in: sceneView)
        
        // Test if the user managed to hit a face of the box
        for (side, node) in box.faces {
            let hitResults = sceneView.hitTest(touchPos, options: [
                .rootNode: node,
                .firstFoundOnly: true,
                ])
            if let result = hitResults.first {
                let coordinatesInBox = box.convertPosition(result.localCoordinates, from: result.node)
                box.highlight(side: side)
                mode = .draggingFace(side: side, dragStart: coordinatesInBox)
                return
            }
        }
    }

    // ---------------------------------------------------
    // --- MODE: DRAGGING FACE (FUNCTIONS)
    
    //called on finger pan
    func handleFaceDrag(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard case let .draggingFace(side, _) = mode else {
            return
        }
        
        switch gestureRecognizer.state {
        case .changed:
            let touchPos = gestureRecognizer.location(in: sceneView)
            if let locationInWorld = scenekitHit(at: touchPos, within: hitTestPlane) {
                // Check where the hit vector landed within the box's own coordinate system, which may be rotated.
                let locationInBox = box.convertPosition(locationInWorld, from: nil)
                
                var distanceForAxis = locationInBox.value(for: side.axis)
                
                // Don't allow the box to be dragged inside-out: stop dragging the side when it meets its opposite side.
                switch side.edge {
                case .min:
                    distanceForAxis = min(distanceForAxis, box.boundingBox.max.value(for: side.axis))
                case .max:
                    distanceForAxis = max(distanceForAxis, box.boundingBox.min.value(for: side.axis))
                }
                
                box.move(side: side, to: distanceForAxis)
            }
        case .ended, .cancelled:
            mode = .waitingForFaceDrag
        default:
            break
        }
    }

}



