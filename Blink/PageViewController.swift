//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import UIKit

// Extracted code from awesome lib https://github.com/rechsteiner/Parchment

protocol PageViewControllerDelegate: AnyObject {
  /// Called whenever the user is about to start scrolling to a view
  /// controller.
  ///
  /// - Parameters:
  ///   - pageViewController: The `PageViewController` instance.
  ///   - startingViewController: The view controller the user is
  ///   scrolling from.
  ///   - destinationViewController: The view controller the user is
  ///   scrolling towards.
  func pageViewController(
    _ pageViewController: PageViewController,
    willStartScrollingFrom startingViewController: UIViewController,
    destinationViewController: UIViewController
  )
  
  /// Called whenever a scroll transition is in progress.
  ///
  /// - Parameters:
  ///   - pageViewController: The `PageViewController` instance.
  ///   - startingViewController: The view controller the user is
  ///   scrolling from.
  ///   - destinationViewController: The view controller the user is
  ///   scrolling towards. Will be nil if the user is scrolling
  ///   towards one of the edges.
  ///   - progress: The progress of the scroll transition. Between 0
  ///   and 1.
  func pageViewController(
    _ pageViewController: PageViewController,
    isScrollingFrom startingViewController: UIViewController,
    destinationViewController: UIViewController?,
    progress: CGFloat
  )
  
  /// Called when the user finished scrolling to a new view.
  ///
  /// - Parameters:
  ///   - pageViewController: The `PageViewController` instance.
  ///   - startingViewController: The view controller the user is
  ///   scrolling from.
  ///   - destinationViewController: The view controller the user is
  ///   scrolling towards.
  ///   - transitionSuccessful: A boolean indicating whether the
  ///   transition completed, or was cancelled by the user.
  func pageViewController(
    _ pageViewController: PageViewController,
    didFinishScrollingFrom startingViewController: UIViewController,
    destinationViewController: UIViewController,
    transitionSuccessful: Bool
  )
}


protocol PageViewControllerDataSource: AnyObject {
  func pageViewController(
    _ pageViewController: PageViewController,
    viewControllerBeforeViewController viewController: UIViewController
  ) -> UIViewController?
  
  func pageViewController(
    _ pageViewController: PageViewController,
    viewControllerAfterViewController viewController: UIViewController
  ) -> UIViewController?
}

class PageViewController: UIViewController {
  private var _scrollView = UIScrollView()
  
  weak var _prevViewController: UIViewController?
  weak var _selectedViewController: UIViewController?
  weak var _nextViewController: UIViewController?
  
  weak var dataSource: PageViewControllerDataSource?
  weak var delegate: PageViewControllerDelegate?
  
  public override var shouldAutomaticallyForwardAppearanceMethods: Bool {
    return false
  }
  
  override func loadView() {
    _scrollView.autoresizingMask = []
    _scrollView.translatesAutoresizingMaskIntoConstraints = false
    _scrollView.bounces = true
    _scrollView.contentInsetAdjustmentBehavior = .never
    _scrollView.showsHorizontalScrollIndicator = false
    _scrollView.showsVerticalScrollIndicator = false
    _scrollView.scrollsToTop = false
    _scrollView.isPagingEnabled = true
    _scrollView.delegate = self
    self.view = _scrollView
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    _appearanceState = .appearing(animated: animated)
    if let selectedViewController = _selectedViewController {
      _beginAppearanceTransition(
        isAppearing: true,
        viewController: selectedViewController,
        animated: animated
      )
    }
    
    switch state {
    case .center, .first, .last, .single:
      _layoutsViews()
    case .empty:
      break
    }
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    _appearanceState = .appeared
    if let selectedViewController = _selectedViewController {
      _endAppearanceTransition(viewController: selectedViewController)
    }
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    _appearanceState = .disappearing(animated: animated)
    if let selectedViewController = _selectedViewController {
      _beginAppearanceTransition(
        isAppearing: false,
        viewController: selectedViewController,
        animated: animated
      )
    }
  }
  
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    _appearanceState = .disappeared
    if let selectedViewController = _selectedViewController {
      _endAppearanceTransition(viewController: selectedViewController)
    }
  }
  
  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    print("viewWillTransition: ", size)
    coordinator.animate(alongsideTransition: { _ in
      self.viewWillTransitionSize()
    })
  }
  
  private var _isRightToLeft: Bool {
    UIView.userInterfaceLayoutDirection(for: view.semanticContentAttribute) == .rightToLeft
  }
  
  private func _didScroll(progress: CGFloat) {
    let currentDirection = PageViewDirection(progress: progress)
    
    // MARK: Begin scrolling
    
    if _initialDirection == .none {
      switch currentDirection {
      case .forward:
        _initialDirection = .forward
        _onScroll(progress: progress)
        _willScrollForward()
      case .reverse:
        _initialDirection = .reverse
        _onScroll(progress: progress)
        _willScrollReverse()
      case .none:
        _onScroll(progress: progress)
      }
    } else {
      // Check if the transition changed direction in the middle of
      // the transactions.
      if _didReload == false {
        switch (currentDirection, _initialDirection) {
        case (.reverse, .forward):
          _initialDirection = .reverse
          _cancelScrollForward()
          _onScroll(progress: progress)
          _willScrollReverse()
        case (.forward, .reverse):
          _initialDirection = .forward
          _cancelScrollReverse()
          _onScroll(progress: progress)
          _willScrollForward()
        default:
          _onScroll(progress: progress)
        }
      } else {
        _onScroll(progress: progress)
      }
    }
    
    // MARK: Finished scrolling
    
    if _didReload == false {
      if progress >= 1 {
        _didReload = true
        _didScrollForward()
      } else if progress <= -1 {
        _didReload = true
        _didScrollReverse()
      } else if progress == 0 {
        switch _initialDirection {
        case .forward:
          _didReload = true
          _cancelScrollForward()
        case .reverse:
          _didReload = true
          _cancelScrollReverse()
        case .none:
          break
        }
      }
    }
  }
  
  private func _onScroll(progress: CGFloat) {
    // This means we are overshooting, so we need to continue
    // reporting the old view controllers.
    if _didReload {
      switch _initialDirection {
      case .forward:
        if let previousViewController = _prevViewController,
           let selectedViewController = _selectedViewController {
          _isScrolling(
            from: previousViewController,
            to: selectedViewController,
            progress: progress
          )
        }
      case .reverse:
        if let nextViewController = _nextViewController,
           let selectedViewController = _selectedViewController {
          _isScrolling(
            from: nextViewController,
            to: selectedViewController,
            progress: progress
          )
        }
      case .none:
        break
      }
    } else {
      // Report progress as normally
      switch _initialDirection {
      case .forward:
        if let selectedViewController = _selectedViewController {
          _isScrolling(
            from: selectedViewController,
            to: _nextViewController,
            progress: progress
          )
        }
      case .reverse:
        if let selectedViewController = _selectedViewController {
          _isScrolling(
            from: selectedViewController,
            to: _prevViewController,
            progress: progress
          )
        }
      case .none:
        break
      }
    }
  }
  
  private func _cancelScrollForward() {
    guard let selectedViewController = _selectedViewController
    else {
      return
    }
    let oldNextViewController = _nextViewController
    
    if let nextViewController = oldNextViewController {
      _beginAppearanceTransition(true, for: selectedViewController, animated: true)
      _beginAppearanceTransition(false, for: nextViewController, animated: true)
    }
    
    if _didSelect {
      let newNextViewController = dataSource?.pageViewController(self, viewControllerAfterViewController: selectedViewController)
      if let oldNextViewController = oldNextViewController {
        _removeViewController(oldNextViewController)
      }
      if let newNextViewController = newNextViewController {
        _addViewController(newNextViewController)
      }
      _nextViewController = newNextViewController
      _didSelect = false
      _layoutsViews()
    }
    
    if let oldNextViewController = oldNextViewController {
      _endAppearanceTransition(for: selectedViewController)
      _endAppearanceTransition(for: oldNextViewController)
      _didFinishScrolling(
        from: selectedViewController,
        to: oldNextViewController,
        transitionSuccessful: false
      )
    }
  }
  
  private func _cancelScrollReverse() {
    guard let selectedViewController = _selectedViewController
    else {
      return
    }
    let oldPreviousViewController = _prevViewController
    
    if let previousViewController = oldPreviousViewController {
      _beginAppearanceTransition(true, for: selectedViewController, animated: true)
      _beginAppearanceTransition(false, for: previousViewController, animated: true)
    }
    
    if _didSelect {
      let newPreviousViewController = dataSource?.pageViewController(self, viewControllerBeforeViewController: selectedViewController)
      if let oldPreviousViewController = oldPreviousViewController {
        _removeViewController(oldPreviousViewController)
      }
      if let newPreviousViewController = newPreviousViewController {
        _addViewController(newPreviousViewController)
      }
      _prevViewController = newPreviousViewController
      _didSelect = false
      _layoutsViews()
    }
    
    if let oldPreviousViewController = oldPreviousViewController {
      _endAppearanceTransition(for: selectedViewController)
      _endAppearanceTransition(for: oldPreviousViewController)
      _didFinishScrolling(
        from: selectedViewController,
        to: oldPreviousViewController,
        transitionSuccessful: false
      )
    }
  }
  
  private func _willScrollForward() {
    if let selectedViewController = _selectedViewController,
       let nextViewController = _nextViewController {
      _willScroll(from: selectedViewController, to: nextViewController)
      _beginAppearanceTransition(true, for: nextViewController, animated: true)
      _beginAppearanceTransition(false, for: selectedViewController, animated: true)
    }
  }
  
  private func _willScrollReverse() {
    if let selectedViewController = _selectedViewController,
       let previousViewController = _prevViewController {
      _willScroll(from: selectedViewController, to: previousViewController)
      _beginAppearanceTransition(true, for: previousViewController, animated: true)
      _beginAppearanceTransition(false, for: selectedViewController, animated: true)
    }
  }
  
  
  private func _didScrollForward() {
    guard
      let oldSelectedViewController = _selectedViewController,
      let oldNextViewController = _nextViewController else { return }
    
    _didFinishScrolling(
      from: oldSelectedViewController,
      to: oldNextViewController,
      transitionSuccessful: true
    )
    
    let newNextViewController = dataSource?.pageViewController(self, viewControllerAfterViewController:oldNextViewController)
    
    if let oldPreviousViewController = _prevViewController {
      if oldPreviousViewController !== newNextViewController {
        _removeViewController(oldPreviousViewController)
      }
    }
    
    if let newNextViewController = newNextViewController {
      if newNextViewController !== _prevViewController {
        _addViewController(newNextViewController)
      }
    }
    
    if _didSelect {
      let newPreviousViewController = dataSource?.pageViewController(self, viewControllerBeforeViewController: oldNextViewController)
      if let oldSelectedViewController = _selectedViewController {
        _removeViewController(oldSelectedViewController)
      }
      if let newPreviousViewController = newPreviousViewController {
        _addViewController(newPreviousViewController)
      }
      _prevViewController = newPreviousViewController
      _didSelect = false
    } else {
      _prevViewController = oldSelectedViewController
    }
    
    _selectedViewController = oldNextViewController
    _nextViewController = newNextViewController
    
    _layoutsViews()
    
    _endAppearanceTransition(for: oldSelectedViewController)
    _endAppearanceTransition(for: oldNextViewController)
  }
  
  
  private func _didScrollReverse() {
    guard
      let oldSelectedViewController = _selectedViewController,
      let oldPreviousViewController = _prevViewController else { return }
    
    _didFinishScrolling(
      from: oldSelectedViewController,
      to: oldPreviousViewController,
      transitionSuccessful: true
    )
    
    let newPreviousViewController = dataSource?.pageViewController(self, viewControllerBeforeViewController: oldPreviousViewController)
    
    if let oldNextViewController = _nextViewController {
      if oldNextViewController !== newPreviousViewController {
        _removeViewController(oldNextViewController)
      }
    }
    
    if let newPreviousViewController = newPreviousViewController {
      if newPreviousViewController !== _nextViewController {
        _addViewController(newPreviousViewController)
      }
    }
    
    if _didSelect {
      let newNextViewController = dataSource?.pageViewController(self, viewControllerAfterViewController: oldPreviousViewController)
      if let oldSelectedViewController = _selectedViewController {
        _removeViewController(oldSelectedViewController)
      }
      if let newNextViewController = newNextViewController {
        _addViewController(newNextViewController)
      }
      _nextViewController = newNextViewController
      _didSelect = false
    } else {
      _nextViewController = oldSelectedViewController
    }
    
    _prevViewController = newPreviousViewController
    _selectedViewController = oldPreviousViewController
    
    _layoutsViews()
    
    _endAppearanceTransition(for: oldSelectedViewController)
    _endAppearanceTransition(for: oldPreviousViewController)
  }
    
  private var _contentOffset: CGFloat {
    get {
      _scrollView.contentOffset.x
    }
    set {
      _scrollView.contentOffset = CGPoint(x: newValue, y: 0)
    }
  }
  
  func viewWillTransitionSize() {
    _layoutsViews(keepContentOffset: false)
  }
  
  enum PageViewState {
    case empty, single, first, center, last
    
    var count: Int {
      switch self {
      case .empty: return 0
      case .single: return 1
      case .first, .last: return 2
      case .center: return 3
      }
    }
  }
  
  private var state: PageViewState {
    if _prevViewController == nil, _nextViewController == nil, _selectedViewController == nil {
      return .empty
    }
    
    if _prevViewController == nil, _nextViewController == nil {
      return .single
    }
    
    if _nextViewController == nil {
      return .last
    }
    if _prevViewController == nil {
      return .first
    }
    return .center
  }
  
  enum PagingDirection: Equatable {
    case reverse(sibling: Bool)
    case forward(sibling: Bool)
    case none
  }
  
  enum PageViewDirection {
    case forward
    case reverse
    case none
    
    init(from direction: PagingDirection) {
      switch direction {
      case .forward:
        self = .forward
      case .reverse:
        self = .reverse
      case .none:
        self = .none
      }
    }
    
    init(progress: CGFloat) {
      if progress > 0 {
        self = .forward
      } else if progress < 0 {
        self = .reverse
      } else {
        self = .none
      }
    }
  }
  
  private enum AppearanceState {
    case appearing(animated: Bool)
    case disappearing(animated: Bool)
    case disappeared
    case appeared
  }
  
  private var _appearanceState: AppearanceState = .disappeared
  private var _didReload: Bool = false
  private var _didSelect: Bool = false
  private var _initialDirection: PageViewDirection = .none
  
  func select(
    viewController: UIViewController,
    direction: PageViewDirection = .none,
    animated: Bool = false
  ) {
    if state == .empty || animated == false {
      _selectViewController(viewController, animated: animated)
      return
    }
    _resetState()
    _didSelect = true
    
    switch direction {
    case .forward, .none:
      if let nextViewController = _nextViewController {
        _removeViewController(nextViewController)
      }
      _addViewController(viewController)
      _nextViewController = viewController
      _layoutsViews()
      _scrollForward()
    case .reverse:
      if let previousViewController = _prevViewController {
        _removeViewController(previousViewController)
      }
      _addViewController(viewController)
      _prevViewController = viewController
      _layoutsViews()
      _scrollReverse()
    }
  }
  
  func selectNext(animated: Bool) {
    if animated {
      _resetState()
      _scrollForward()
      return
    }
    
    if let nextViewController = _nextViewController,
       let selectedViewController = _selectedViewController {
      _beginAppearanceTransition(false, for: selectedViewController, animated: animated)
      _beginAppearanceTransition(true, for: nextViewController, animated: animated)
      
      let newNextViewController = dataSource?.pageViewController(self, viewControllerAfterViewController: nextViewController)
      
      if let previousViewController = _prevViewController {
        _removeViewController(previousViewController)
      }
      
      if let newNextViewController = newNextViewController {
        _addViewController(newNextViewController)
      }
      
      _prevViewController = selectedViewController
      _selectedViewController = nextViewController
      _nextViewController = newNextViewController
      
      _layoutsViews()
      
      _endAppearanceTransition(for: selectedViewController)
      _endAppearanceTransition(for: nextViewController)
    }
  }
  
  func selectPrevious(animated: Bool) {
    if animated {
      _resetState()
      _scrollReverse()
      return
    }
    if let previousViewController = _prevViewController,
       let selectedViewController = _selectedViewController {
      _beginAppearanceTransition(false, for: selectedViewController, animated: animated)
      _beginAppearanceTransition(true, for: previousViewController, animated: animated)
      
      let newPreviousViewController = dataSource?.pageViewController(self, viewControllerBeforeViewController: previousViewController)
      
      if let nextViewController = _nextViewController {
        _removeViewController(nextViewController)
      }
      
      if let newPreviousViewController = newPreviousViewController {
        _addViewController(newPreviousViewController)
      }
      
      _prevViewController = newPreviousViewController
      _selectedViewController = previousViewController
      _nextViewController = selectedViewController
      
      _layoutsViews()
      
      _endAppearanceTransition(for: selectedViewController)
      _endAppearanceTransition(for: previousViewController)
    }
  }
  
  func removeAll() {
    let oldSelectedViewController = _selectedViewController
    
    if let selectedViewController = oldSelectedViewController {
      _beginAppearanceTransition(false, for: selectedViewController, animated: false)
      _removeViewController(selectedViewController)
    }
    if let previousViewController = _prevViewController {
      _removeViewController(previousViewController)
    }
    if let nextViewController = _nextViewController {
      _removeViewController(nextViewController)
    }
    _prevViewController = nil
    _selectedViewController = nil
    _nextViewController = nil
    _layoutsViews()
    
    if let oldSelectedViewController = oldSelectedViewController {
      _endAppearanceTransition(for: oldSelectedViewController)
    }
  }
  
  func removeSides() {
    if let prev = _prevViewController {
      _removeViewController(prev)
      _prevViewController = nil
    }
    
    if let next = _nextViewController {
      _removeViewController(next)
      _nextViewController = nil
    }
    
    _layoutsViews()
  }
  
  func restoreSides() {
    guard let selected = _selectedViewController
    else {
      return
    }
    if _prevViewController == nil,
       let ctrl = dataSource?.pageViewController(self, viewControllerBeforeViewController: selected)  {
       _prevViewController = ctrl
      _addViewController(ctrl)
    }
    if _nextViewController == nil,
       let ctrl = dataSource?.pageViewController(self, viewControllerAfterViewController: selected) {
      _nextViewController = ctrl
      _addViewController(ctrl)
    }
    _layoutsViews()
  }
  
  private func _selectViewController(_ viewController: UIViewController, animated: Bool) {
    let oldSelectedViewController = _selectedViewController
    let newPreviousViewController = dataSource?.pageViewController(self, viewControllerBeforeViewController: viewController)
    let newNextViewController = dataSource?.pageViewController(self, viewControllerAfterViewController: viewController)
    
    if let oldSelectedViewController = oldSelectedViewController {
      _beginAppearanceTransition(false, for: oldSelectedViewController, animated: animated)
    }
    
    if viewController !== _selectedViewController {
      _beginAppearanceTransition(true, for: viewController, animated: animated)
    }
    
    if let oldPreviosViewController = _prevViewController {
      if oldPreviosViewController !== viewController,
         oldPreviosViewController !== newPreviousViewController,
         oldPreviosViewController !== newNextViewController {
        _removeViewController(oldPreviosViewController)
      }
    }
    
    if let oldSelectedViewController = _selectedViewController {
      if oldSelectedViewController !== newPreviousViewController,
         oldSelectedViewController !== newNextViewController {
        _removeViewController(oldSelectedViewController)
      }
    }
    
    if let oldNextViewController = _nextViewController {
      if oldNextViewController !== viewController,
         oldNextViewController !== newPreviousViewController,
         oldNextViewController !== newNextViewController {
        _removeViewController(oldNextViewController)
      }
    }
    
    if let newPreviousViewController = newPreviousViewController {
      if newPreviousViewController !== _selectedViewController,
         newPreviousViewController !== _prevViewController,
         newPreviousViewController !== _nextViewController {
        _addViewController(newPreviousViewController)
      }
    }
    
    if viewController !== _nextViewController,
       viewController !== _prevViewController {
      _addViewController(viewController)
    }
    
    if let newNextViewController = newNextViewController {
      if newNextViewController !== _selectedViewController,
         newNextViewController !== _prevViewController,
         newNextViewController !== _nextViewController {
        _addViewController(newNextViewController)
      }
    }
    
    _prevViewController = newPreviousViewController
    _selectedViewController = viewController
    _nextViewController = newNextViewController
    
    _layoutsViews()
    
    if let oldSelectedViewController = oldSelectedViewController {
      _endAppearanceTransition(for: oldSelectedViewController)
    }
    
    if viewController !== oldSelectedViewController {
      _endAppearanceTransition(for: viewController)
    }
  }
  
  private func _resetState() {
    if _didReload {
      _initialDirection = .none
    }
    _didReload = false
  }
  
  private func _layoutsViews(keepContentOffset: Bool = true) {
    var viewControllers: [UIViewController] = []
    
    if let previousViewController = _prevViewController {
      viewControllers.append(previousViewController)
    }
    if let selectedViewController = _selectedViewController {
      viewControllers.append(selectedViewController)
    }
    if let nextViewController = _nextViewController {
      viewControllers.append(nextViewController)
    }
    
    viewControllers = _isRightToLeft ? viewControllers.reversed() : viewControllers
    
    // Need to trigger a layout here to ensure that the scroll view
    // bounds is updated before we use its frame for calculations.
    view.layoutIfNeeded()
    
    let pageSize = view.bounds.size
    
    for (index, viewController) in viewControllers.enumerated() {
      viewController.view.frame = CGRect(
        x: CGFloat(index) * pageSize.width,
        y: 0,
        width: pageSize.width,
        height: pageSize.height
      )
    }
    
    // When updating the content offset we need to account for the
    // current content offset as well. This ensures that the selected
    // page is fully centered when swiping so fast that you get the
    // bounce effect in the scroll view.
    var diff: CGFloat = 0
    
    if keepContentOffset {
      if _contentOffset > pageSize.width * 2 {
        diff = _contentOffset - pageSize.width * 2
      } else if _contentOffset > pageSize.width, _contentOffset < pageSize.width * 2 {
        diff = _contentOffset - pageSize.width
      } else if _contentOffset < pageSize.width, _contentOffset < 0 {
        diff = _contentOffset
      }
    }
    
    // Need to set content size before updating content offset. If not
    // the views will be misplaced when overshooting.
    _scrollView.contentSize = CGSize(
      width: CGFloat(state.count) * pageSize.width,
      height: pageSize.height
    )
    
    if _isRightToLeft {
      switch state {
      case .first, .center:
        _contentOffset = pageSize.width + diff
      case .single, .empty, .last:
        _contentOffset = diff
      }
    } else {
      switch state {
      case .first, .single, .empty:
        _contentOffset = diff
      case .last, .center:
        _contentOffset = pageSize.width + diff
      }
    }
  }
  
  private func _beginAppearanceTransition(
    _ isAppearing: Bool,
    for viewController: UIViewController,
    animated: Bool
  ) {
    switch _appearanceState {
    case .appeared:
      _beginAppearanceTransition(
        isAppearing: isAppearing,
        viewController: viewController,
        animated: animated
      )
    case let .appearing(animated):
      // Override the given animated flag with the animated flag of
      // the parent views appearance transition.
      _beginAppearanceTransition(
        isAppearing: isAppearing,
        viewController: viewController,
        animated: animated
      )
    case let .disappearing(animated):
      // When the parent view is about to disappear we always set
      // isAppearing to false.
      _beginAppearanceTransition(
        isAppearing: false,
        viewController: viewController,
        animated: animated
      )
    default:
      break
    }
  }
  
  private func _endAppearanceTransition(for viewController: UIViewController) {
    guard case .appeared = _appearanceState
    else {
      return
    }
    _endAppearanceTransition(viewController: viewController)
  }
  
  
  func _setContentOffset(_ value: CGFloat, animated: Bool) {
    _scrollView.setContentOffset(CGPoint(x: value, y: 0), animated: animated)
  }
  
  private func _scrollForward() {
    if _isRightToLeft {
      switch state {
      case .first, .center:
        _setContentOffset(.zero, animated: true)
      case .single, .empty, .last:
        break
      }
    } else {
      let pageSize = view.bounds.width
      switch state {
      case .first:
        _setContentOffset(pageSize, animated: true)
      case .center:
        _setContentOffset(pageSize * 2, animated: true)
      case .single, .empty, .last:
        break
      }
    }
  }
  
  private func _scrollReverse() {
    if _isRightToLeft {
      let pageSize = view.bounds.width
      switch state {
      case .last:
        _setContentOffset(pageSize, animated: true)
      case .center:
        _setContentOffset(pageSize * 2, animated: true)
      case .single, .empty, .first:
        break
      }
    } else {
      switch state {
      case .last, .center:
        _scrollView.setContentOffset(.zero, animated: true)
      case .single, .empty, .first:
        break
      }
    }
  }
  
  private func _addViewController(_ viewController: UIViewController) {
    viewController.willMove(toParent: self)
    addChild(viewController)
    _scrollView.addSubview(viewController.view)
    viewController.didMove(toParent: self)
  }
  
  private func _removeViewController(_ viewController: UIViewController) {
    viewController.willMove(toParent: nil)
    viewController.removeFromParent()
    viewController.view.removeFromSuperview()
    viewController.didMove(toParent: nil)
  }
  
  private func _beginAppearanceTransition(isAppearing: Bool, viewController: UIViewController, animated: Bool) {
    viewController.beginAppearanceTransition(isAppearing, animated: animated)
  }
  
  private func _endAppearanceTransition(viewController: UIViewController) {
    viewController.endAppearanceTransition()
  }
  
  private func _willScroll(
    from selectedViewController: UIViewController,
    to destinationViewController: UIViewController
  ) {
    delegate?.pageViewController(
      self,
      willStartScrollingFrom: selectedViewController,
      destinationViewController: destinationViewController
    )
  }
  
  private func _didFinishScrolling(
    from selectedViewController: UIViewController,
    to destinationViewController: UIViewController,
    transitionSuccessful: Bool
  ) {
    delegate?.pageViewController(
      self,
      didFinishScrollingFrom: selectedViewController,
      destinationViewController: destinationViewController,
      transitionSuccessful: transitionSuccessful
    )
  }
  
  private func _isScrolling(
    from selectedViewController: UIViewController,
    to destinationViewController: UIViewController?,
    progress: CGFloat
  ) {
    delegate?.pageViewController(
      self,
      isScrollingFrom: selectedViewController,
      destinationViewController: destinationViewController,
      progress: progress
    )
  }
  
}

extension PageViewController: UIScrollViewDelegate {
  public func scrollViewWillBeginDragging(_: UIScrollView) {
    _resetState()
  }
  
  public func scrollViewWillEndDragging(_: UIScrollView, withVelocity _: CGPoint, targetContentOffset _: UnsafeMutablePointer<CGPoint>) {
    _resetState()
  }
  
  public func scrollViewDidScroll(_: UIScrollView) {
    let distance = view.bounds.width
    var progress: CGFloat
    
    if _isRightToLeft {
      switch state {
      case .last, .empty, .single:
        progress = -(_contentOffset / distance)
      case .center, .first:
        progress = -((_contentOffset - distance) / distance)
      }
    } else {
      switch state {
      case .first, .empty, .single:
        progress = _contentOffset / distance
      case .center, .last:
        progress = (_contentOffset - distance) / distance
      }
    }
    
    _didScroll(progress: progress)
  }
  
  func setViewControllers(_ viewControllers: [UIViewController]?,
                direction: UIPageViewController.NavigationDirection,
                 animated: Bool) {
    guard let vc = viewControllers?.first
    else {
      removeAll()
      return
    }
    let dir: PageViewDirection = direction == .forward ? .forward : .reverse
    select(viewController: vc, direction: dir, animated: animated)
    
  }
}
